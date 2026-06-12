variable "project_name"    { type = string }
variable "environment"     { type = string }
variable "owner"           { type = string }
variable "team"            { type = string }
variable "cost_center"     { type = string }
variable "additional_tags" { 
  type = map(string)
  default = {} 
}

# ─── Resource Group existente ─────────────────────────────────────────────────

variable "resource_group_name" {
  description = "Resource Group name."
  type        = string

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name cannot be empty."
  }
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vnet_address_space" {
  description = "VNet address space."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "public_subnet_prefix" {
  description = "CIDR for the public subnet (endpoints, load balancers)."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrhost(var.public_subnet_prefix, 0))
    error_message = "public_subnet_prefix must be a valid CIDR."
  }
}

variable "private_subnet_prefix" {
  description = "CIDR for the private subnet (inter-service communication)."
  type        = string
  default     = "10.0.10.0/24"

  validation {
    condition     = can(cidrhost(var.private_subnet_prefix, 0))
    error_message = "private_subnet_prefix must be a valid CIDR."
  }
}