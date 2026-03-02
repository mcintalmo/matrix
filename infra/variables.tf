# Terraform Variables for Oracle Cloud Infrastructure
# Copy this to terraform.tfvars and fill in your values

# OCI Authentication
variable "tenancy_ocid" {
  description = "OCI Tenancy OCID - Find in OCI Console > Profile > Tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCI User OCID - Find in OCI Console > Profile > User Settings"
  type        = string
}

variable "compartment_ocid" {
  description = "OCI Compartment OCID - Find in OCI Console > Identity > Compartments"
  type        = string
}

variable "region" {
  description = "OCI Region (e.g., us-ashburn-1, us-phoenix-1)"
  type        = string
  default     = "us-ashburn-1"
}

variable "fingerprint" {
  description = "OCI API Key Fingerprint - Generated when you create API keys"
  type        = string
}

variable "private_key_path" {
  description = "Path to OCI API private key (PEM format)"
  type        = string
  default     = "~/.oci/oci_api_key.pem"
}

# SSH Access
variable "ssh_public_key_path" {
  description = "Path to SSH public key for instance access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "my_ip_cidr" {
  description = "Your IP address for SSH access in CIDR notation (e.g., 1.2.3.4/32). Use 0.0.0.0/0 to allow from anywhere (NOT RECOMMENDED for production)"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.my_ip_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 198.51.100.1/32)."
  }
}

# Instance Configuration
variable "instance_shape" {
  description = "OCI compute shape"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Number of OCPUs for the instance"
  type        = number
  default     = 2

  validation {
    condition     = var.instance_ocpus >= 1 && var.instance_ocpus <= 4
    error_message = "OCPUs must be between 1 and 4 for Free Tier (A1.Flex)."
  }
}

variable "instance_memory_gb" {
  description = "Memory in GB for the instance"
  type        = number
  default     = 12

  validation {
    condition     = var.instance_memory_gb >= 6 && var.instance_memory_gb <= 24
    error_message = "Memory must be between 6GB and 24GB for Free Tier (A1.Flex)."
  }
}

variable "ad_number" {
  type        = number
  description = "The Availability Domain number to try (1, 2, or 3)"
  default     = 1

  validation {
    condition     = var.ad_number >= 1 && var.ad_number <= 3
    error_message = "Availability Domain must be 1, 2, or 3."
  }
}

# Tags
variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be production, staging, or development."
  }
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "matrix"

  validation {
    condition     = length(var.project_name) > 0 && length(var.project_name) <= 50
    error_message = "Project name must be 1-50 characters."
  }
}

