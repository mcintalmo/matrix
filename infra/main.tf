terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 8.1.0"
    }
  }
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# 1. Networking (VCN, Subnet, Security List)
resource "oci_core_vcn" "matrix_vcn" {
  cidr_block     = "10.0.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-vcn"
  freeform_tags  = local.common_tags
}

resource "oci_core_internet_gateway" "matrix_ig" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.matrix_vcn.id
  display_name   = "${local.name_prefix}-ig"
  freeform_tags  = local.common_tags
}

resource "oci_core_route_table" "matrix_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.matrix_vcn.id
  display_name   = "${local.name_prefix}-rt"
  freeform_tags  = local.common_tags
  
  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.matrix_ig.id
  }
}

resource "oci_core_security_list" "matrix_sl" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.matrix_vcn.id
  display_name   = "${local.name_prefix}-security-list"
  freeform_tags  = local.common_tags

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Allow SSH
  ingress_security_rules {
    protocol = "6" # TCP
    source   = var.my_ip_cidr
    tcp_options {
      min = 22
      max = 22
    }
  }

  # Allow HTTP/HTTPS
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 80
      max = 80
    }
  }
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 443
      max = 443
    }
  }
  
  # Allow Matrix Federation (8448) & TURN (3478)
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 8448
      max = 8448
    }
  }
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 3478
      max = 3478
    }
  }
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 3478
      max = 3478
    }
  }
  
  # Allow TURN UDP port range for media relay
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 49152
      max = 49172
    }
  }

  # Allow LiveKit WebRTC SFU UDP port range
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 50000
      max = 50200
    }
  }

  # Allow LiveKit WebRTC SFU TCP fallback port
  ingress_security_rules {
    protocol = "6" # TCP
    source   = "0.0.0.0/0"
    tcp_options {
      min = 7881
      max = 7881
    }
  }
}

resource "oci_core_subnet" "matrix_subnet" {
  cidr_block        = "10.0.1.0/24"
  compartment_id    = var.compartment_ocid
  vcn_id            = oci_core_vcn.matrix_vcn.id
  route_table_id    = oci_core_route_table.matrix_rt.id
  security_list_ids = [oci_core_security_list.matrix_sl.id]
  display_name      = "${local.name_prefix}-subnet"
  freeform_tags     = local.common_tags
}

# 2. Get the Latest Ubuntu ARM Image
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# 3. Get Availability Domain
data "oci_identity_availability_domain" "ad" {
  compartment_id = var.tenancy_ocid
  ad_number      = var.ad_number
}

# 4. Compute Instance (The VPS)
resource "oci_core_instance" "matrix_server" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = "${local.name_prefix}-server"
  shape               = var.instance_shape
  freeform_tags       = merge(local.common_tags, {
    Name        = "Matrix Synapse Server"
    Application = "matrix-synapse"
    BackupDaily = "true"
  })

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_memory_gb
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.matrix_subnet.id
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu_arm.images[0].id
  }



  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  lifecycle {
    ignore_changes = [
      # Oracle sometimes auto-updates these fields, causing "drift". 
      # Ignoring them keeps your state clean.
      metadata,
      source_details[0].source_id
    ]
    prevent_destroy = true
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data           = base64encode(file("./cloud-init.yaml"))
  }
}

resource "oci_budget_budget" "budget" {
  compartment_id = var.tenancy_ocid
  amount         = 1 # $1.00 USD
  reset_period   = "MONTHLY"
  description    = "Safety net for Matrix server"
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_ocid]
}

resource "oci_budget_alert_rule" "budget_alert" {
  budget_id      = oci_budget_budget.budget.id
  type           = "ACTUAL"
  threshold      = 100 # 100% of $1.00
  threshold_type = "PERCENTAGE"
  description    = "Alert me if I spend more than $1"
  recipients     = "mcintalmo@gmail.com"
  message        = "WARNING: You are spending money on Oracle Cloud!"
}

# ── Object Storage ────────────────────────────────────────────────────────────

# Get the tenancy's Object Storage namespace (required by OCI)
data "oci_objectstorage_namespace" "ns" {
  compartment_id = var.compartment_ocid
}

# The backup bucket (Always Free tier: up to 20 GB)
resource "oci_objectstorage_bucket" "matrix_backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.ns.namespace
  name           = "matrix-backups"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
  freeform_tags  = local.common_tags
}

# ── Instance Principal Auth ───────────────────────────────────────────────────
# Lets the Matrix server VM authenticate to OCI APIs as itself,
# so backup.sh needs no embedded credentials (like AWS instance roles).

resource "oci_identity_dynamic_group" "matrix_instances" {
  compartment_id = var.tenancy_ocid
  name           = "matrix-server-instances"
  description    = "Dynamic group for Matrix server VMs (allows Instance Principal auth)"
  matching_rule  = "All {instance.compartment.id = '${var.compartment_ocid}'}"
  freeform_tags  = local.common_tags
}

resource "oci_identity_policy" "matrix_backup_policy" {
  compartment_id = var.tenancy_ocid
  name           = "matrix-backup-policy"
  description    = "Allows Matrix server to read/write the backup Object Storage bucket"
  freeform_tags  = local.common_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.matrix_instances.name} to manage objects in compartment id ${var.compartment_ocid} where target.bucket.name='matrix-backups'",
    "Allow dynamic-group ${oci_identity_dynamic_group.matrix_instances.name} to read buckets in compartment id ${var.compartment_ocid}",
  ]
}