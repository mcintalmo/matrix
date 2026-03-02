# Terraform State Management
# 
# OPTION 1: OCI Object Storage (Recommended - Free Tier includes storage)
# Uncomment and configure after creating a bucket in OCI Console

# terraform {
#   backend "s3" {
#     bucket                      = "matrix-terraform-state"
#     key                         = "matrix/terraform.tfstate"
#     region                      = "us-ashburn-1"
#     endpoint                    = "https://namespace.compat.objectstorage.us-ashburn-1.oraclecloud.com"
#     skip_region_validation      = true
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     force_path_style            = true
#   }
# }

# OPTION 2: Terraform Cloud (Free for up to 500 resources)
# terraform {
#   backend "remote" {
#     organization = "your-org-name"
#     workspaces {
#       name = "matrix-production"
#     }
#   }
# }

# For now: Local state - keep terraform.tfstate in .gitignore
