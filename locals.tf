locals {
  name_prefix = "${var.project_name}-${var.environment}"

  base_tags = {
    project     = var.project_name
    environment = var.environment
    owner       = var.owner
    team        = var.team
    cost_center = var.cost_center
    managed_by  = "terraform"
  }

  tags = merge(local.base_tags, var.additional_tags)
}