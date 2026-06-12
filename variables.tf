variable "project_name" {
  description = "Project name. Use only lowercase letters, numbers, and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name can only contain lowercase letters, numbers, and hyphens (-)."
  }
  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 20
    error_message = "project_name must be between 3 and 20 characters."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "qa", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, staging, prod."
  }
}

variable "owner" {
  description = "Email of the resource owner."
  type        = string

  validation {
    condition = can(
      regex(
        "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
        var.owner
      )
    )
    error_message = "owner must be a valid email (e.g., user@apexsystems.com)."
  }
}

variable "team" {
  description = "Team owning the resource."
  type        = string

  validation {
    condition     = length(trimspace(var.team)) > 0
    error_message = "team cannot be empty."
  }
}

variable "cost_center" {
  description = "Cost center. Format: CC-XXXX"
  type        = string

  validation {
    condition     = can(regex("^CC-[0-9]{4}$", var.cost_center))
    error_message = "cost_center must be in the format CC-XXXX (e.g., CC-1234)."
  }
}

variable "additional_tags" {
  description = "Optional additional tags/labels."
  type        = map(string)
  default     = {}
}