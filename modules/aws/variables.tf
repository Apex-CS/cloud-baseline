variable "project_name"    { type = string }
variable "environment"     { type = string }
variable "owner"           { type = string }
variable "team"            { type = string }
variable "cost_center"     { type = string }
variable "additional_tags" { 
    type = map(string)
    default = {}
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (endpoints, load balancers). One per AZ recommended."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 1
    error_message = "There must be at least one public subnet."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private subnets (inter-service communication)."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 1
    error_message = "There must be at least one private subnet."
  }
}

variable "enable_nat_gateway" {
  description = "Enables NAT Gateway for internet access from private subnets. Additional cost applies."
  type        = bool
  default     = true
}