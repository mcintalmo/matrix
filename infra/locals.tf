# Local Variables & Common Tags
# These are reusable values for tagging and naming

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "infrastructure-team"
  }

  # Consistent naming convention
  name_prefix = "${var.project_name}-${var.environment}"
}
