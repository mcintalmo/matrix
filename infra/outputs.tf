# Terraform Outputs

output "server_public_ip" {
  description = "Public IP address of the Matrix server"
  value       = oci_core_instance.matrix_server.public_ip
}

output "server_private_ip" {
  description = "Private IP address of the Matrix server"
  value       = oci_core_instance.matrix_server.private_ip
}

output "server_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.matrix_server.id
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.matrix_vcn.id
}

output "subnet_id" {
  description = "OCID of the subnet"
  value       = oci_core_subnet.matrix_subnet.id
}

output "ssh_connection_string" {
  description = "SSH connection string"
  value       = "ssh ubuntu@${oci_core_instance.matrix_server.public_ip}"
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
  
  ═══════════════════════════════════════════════════════════════
  🎉 Infrastructure deployed successfully!
  ═══════════════════════════════════════════════════════════════
  
  Server IP: ${oci_core_instance.matrix_server.public_ip}
  
  Next steps:
  
  1. SSH into the server:
     ssh ubuntu@${oci_core_instance.matrix_server.public_ip}
  
  2. Wait for cloud-init to complete (may take 5-10 minutes):
     tail -f /var/log/cloud-init-output.log
  
  3. Update your DNS:
     Add A record: matrix.rumpusroom.xyz → ${oci_core_instance.matrix_server.public_ip}
  
  4. Clone your repo and set up Matrix:
     git clone <your-repo>
     cd matrix
     # Follow deployment instructions in README
  
  5. Configure SSL certificates:
     sudo certbot --nginx -d matrix.rumpusroom.xyz
  
  ═══════════════════════════════════════════════════════════════
  EOT
}

output "backup_bucket_url" {
  description = "OCI Object Storage URL for the Matrix backup bucket"
  value       = "https://objectstorage.${var.region}.oraclecloud.com/n/${data.oci_objectstorage_namespace.ns.namespace}/b/matrix-backups"
}
