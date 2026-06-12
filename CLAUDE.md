# CLAUDE.md — cloud-baseline Terraform Module

This file gives Claude (and other AI assistants) a complete reference for working with this repository.

---

## Overview

`cloud-baseline` is a **multi-cloud Terraform baseline library** intended for use as a reusable module by downstream project deployments. It provides three core capabilities:

1. **Standardized naming** — every cloud resource gets a consistent `<project_name>-<environment>` name prefix.
2. **Standardized tagging** — a validated, mandatory governance tag map (owner, team, cost_center, etc.) flows automatically to all cloud resources.
3. **Baseline networking** — cloud-specific child modules provision a production-ready VPC/VNet with public and private subnets, routing, and security controls.

**The root module provisions zero cloud resources.** It is pure logic: input validation, naming, and tagging. All cloud infrastructure lives in the child modules under `modules/`.

---

## Repository Structure

```
cloud-baseline/
├── locals.tf                  # name_prefix and merged tags
├── outputs.tf                 # Exposes name_prefix and tags
├── variables.tf               # Project metadata + governance inputs (all validated)
├── versions.tf                # Terraform >= 1.5.0 constraint
├── README.md
└── modules/
    ├── aws/
    │   ├── main.tf            # VPC, subnets, IGW, NAT GW, route tables
    │   ├── outputs.tf         # VPC/subnet/gateway IDs + name_prefix/tags
    │   ├── variables.tf       # AWS-specific vars + inherited base vars
    │   └── versions.tf        # Terraform >= 1.5.0, AWS provider ~> 5.0
    └── azure/
        ├── main.tf            # VNet, subnets, NSGs, NSG associations
        ├── outputs.tf         # VNet/subnet IDs + name_prefix/tags/RG info
        ├── variables.tf       # Azure-specific vars + inherited base vars
        └── versions.tf        # Terraform >= 1.5.0, AzureRM provider ~> 3.0
```

No `.tfvars` files are tracked (`.gitignore` excludes them). No `backend` or `provider` blocks exist in any module — these are the caller's responsibility.

---

## Composition Architecture

```
Downstream caller
  └── modules/aws  OR  modules/azure   (cloud-specific child module)
        └── module "base" { source = "../../" }   (root module: naming + tagging)
```

Each cloud child module calls the root as `module "base"`, receives `name_prefix` and `tags`, and uses those to name and tag every resource it creates. The caller only interacts with one child module.

---

## Root Module Reference

### Purpose
Validates all governance inputs, assembles the name prefix and tag map, exposes them as outputs. No cloud provider required.

### Variables

| Variable | Type | Required | Default | Validation Rule |
|---|---|---|---|---|
| `project_name` | `string` | Yes | — | Regex `^[a-z0-9-]+$`; length 3–20 chars |
| `environment` | `string` | Yes | — | Must be one of: `dev`, `qa`, `staging`, `prod` |
| `owner` | `string` | Yes | — | Must be a valid email address |
| `team` | `string` | Yes | — | Cannot be empty or whitespace-only |
| `cost_center` | `string` | Yes | — | Must match `^CC-[0-9]{4}$`, e.g., `CC-1234` |
| `additional_tags` | `map(string)` | No | `{}` | Merged on top of base tags |

### Key Locals

| Local | Expression | Example Value |
|---|---|---|
| `name_prefix` | `"${var.project_name}-${var.environment}"` | `"payments-api-prod"` |
| `base_tags` | Map of 6 hardcoded governance tags | see Tagging section |
| `tags` | `merge(local.base_tags, var.additional_tags)` | All tags merged |

### Outputs

| Output | Description |
|---|---|
| `name_prefix` | Resource naming prefix, e.g., `payments-api-prod` |
| `tags` | Fully merged tag map, ready to assign to any resource |

### Version Constraint
```hcl
terraform { required_version = ">= 1.5.0" }
```

---

## `modules/aws` Reference

### What It Deploys

A complete, self-contained AWS VPC networking stack:

| Resource | Description |
|---|---|
| `aws_vpc.main` | VPC with DNS hostnames and DNS support enabled |
| `aws_internet_gateway.main` | IGW attached to the VPC |
| `aws_subnet.public[*]` | One per CIDR in `public_subnet_cidrs`; `map_public_ip_on_launch = true`; round-robin across AZs |
| `aws_subnet.private[*]` | One per CIDR in `private_subnet_cidrs`; no public IPs; round-robin across AZs |
| `aws_eip.nat[0]` | Elastic IP for NAT Gateway (only when `enable_nat_gateway = true`) |
| `aws_nat_gateway.main[0]` | NAT GW in `public[0]`; enables private subnet egress (conditional) |
| `aws_route_table.public` | Routes `0.0.0.0/0` → IGW |
| `aws_route_table.private` | Routes `0.0.0.0/0` → NAT GW when enabled; no default route otherwise |
| `aws_route_table_association.public[*]` | Associates all public subnets to the public route table |
| `aws_route_table_association.private[*]` | Associates all private subnets to the private route table |
| `terraform_data.aws_tag_validation` | Plan-time precondition: total tag count must not exceed 50 |

**Data source:** `data.aws_availability_zones.available` — AZs distributed dynamically via `count.index % length(az_names)`.

### Variables

**Inherited from root (re-declared, root validates these):**

| Variable | Type | Required |
|---|---|---|
| `project_name` | `string` | Yes |
| `environment` | `string` | Yes |
| `owner` | `string` | Yes |
| `team` | `string` | Yes |
| `cost_center` | `string` | Yes |
| `additional_tags` | `map(string)` | No (default `{}`) |

**AWS-specific:**

| Variable | Type | Required | Default | Notes |
|---|---|---|---|---|
| `vpc_cidr` | `string` | No | `"10.0.0.0/16"` | Validated with `cidrhost()` |
| `public_subnet_cidrs` | `list(string)` | No | `["10.0.1.0/24", "10.0.2.0/24"]` | Minimum 1 entry |
| `private_subnet_cidrs` | `list(string)` | No | `["10.0.10.0/24", "10.0.20.0/24"]` | Minimum 1 entry |
| `enable_nat_gateway` | `bool` | No | `true` | Creates EIP + NAT GW; adds AWS cost |

### Outputs

| Output | Description |
|---|---|
| `name_prefix` | Standardized resource naming prefix |
| `tags` | Full merged tag map |
| `vpc_id` | VPC ID |
| `vpc_cidr` | VPC CIDR block |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `internet_gateway_id` | Internet Gateway ID |
| `nat_gateway_id` | NAT Gateway ID, or `null` when disabled |

### Naming Convention

All resources: `"${module.base.name_prefix}-<suffix>"`

| Resource | Name Pattern | Example |
|---|---|---|
| VPC | `<prefix>-vpc` | `payments-api-prod-vpc` |
| Public subnet N | `<prefix>-public-N` | `payments-api-prod-public-1` |
| Private subnet N | `<prefix>-private-N` | `payments-api-prod-private-1` |
| Internet Gateway | `<prefix>-igw` | `payments-api-prod-igw` |
| NAT Gateway | `<prefix>-nat` | `payments-api-prod-nat` |
| Route tables | `<prefix>-public-rt` / `<prefix>-private-rt` | `payments-api-prod-public-rt` |

### Version Constraints
```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}
```

---

## `modules/azure` Reference

### Prerequisites

The Azure module requires a **pre-existing Resource Group**. Pass its name via `resource_group_name`. The module reads it with a data source and will fail if the RG does not exist. It does **not** create or destroy the RG.

### What It Deploys

| Resource | Description |
|---|---|
| `azurerm_virtual_network.main` | VNet with configurable address space |
| `azurerm_subnet.public` | Single public-tier subnet |
| `azurerm_subnet.private` | Single private-tier subnet |
| `azurerm_network_security_group.public` | Allows HTTP (80) and HTTPS (443) inbound |
| `azurerm_network_security_group.private` | Allows `VirtualNetwork` inbound; denies `Internet` inbound |
| `azurerm_subnet_network_security_group_association.public` | Binds public NSG to public subnet |
| `azurerm_subnet_network_security_group_association.private` | Binds private NSG to private subnet |

**Data source:** `data.azurerm_resource_group.main` — provides `location`, `name`, and `id`.

### NSG Rules

| NSG | Rule Name | Priority | Direction | Protocol | Port | Source | Action |
|---|---|---|---|---|---|---|---|
| Public | `allow-http` | 100 | Inbound | TCP | 80 | `*` | Allow |
| Public | `allow-https` | 110 | Inbound | TCP | 443 | `*` | Allow |
| Private | `allow-vnet-inbound` | 100 | Inbound | `*` | `*` | `VirtualNetwork` | Allow |
| Private | `deny-internet-inbound` | 200 | Inbound | `*` | `*` | `Internet` | Deny |

### Variables

**Inherited from root (re-declared):**

| Variable | Type | Required |
|---|---|---|
| `project_name` | `string` | Yes |
| `environment` | `string` | Yes |
| `owner` | `string` | Yes |
| `team` | `string` | Yes |
| `cost_center` | `string` | Yes |
| `additional_tags` | `map(string)` | No (default `{}`) |

**Azure-specific:**

| Variable | Type | Required | Default | Notes |
|---|---|---|---|---|
| `resource_group_name` | `string` | Yes | — | Must be a non-empty string; RG must pre-exist |
| `vnet_address_space` | `list(string)` | No | `["10.0.0.0/16"]` | VNet address space list |
| `public_subnet_prefix` | `string` | No | `"10.0.1.0/24"` | Validated with `cidrhost()` |
| `private_subnet_prefix` | `string` | No | `"10.0.10.0/24"` | Validated with `cidrhost()` |

### Outputs

| Output | Description |
|---|---|
| `name_prefix` | Standardized naming prefix |
| `tags` | Full merged tag/label map |
| `resource_group_name` | Resource Group name as resolved |
| `resource_group_id` | Resource Group ARM ID |
| `location` | Azure region (inherited from the RG) |
| `vnet_id` | Virtual Network ARM ID |
| `vnet_name` | Virtual Network name |
| `public_subnet_id` | Public subnet ARM ID |
| `private_subnet_id` | Private subnet ARM ID |

### Naming Convention

Follows [Microsoft CAF abbreviations](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations):

| Resource | Name Pattern | Example |
|---|---|---|
| VNet | `vnet-<prefix>` | `vnet-payments-api-prod` |
| Public subnet | `snet-public-<prefix>` | `snet-public-payments-api-prod` |
| Private subnet | `snet-private-<prefix>` | `snet-private-payments-api-prod` |
| Public NSG | `nsg-public-<prefix>` | `nsg-public-payments-api-prod` |
| Private NSG | `nsg-private-<prefix>` | `nsg-private-payments-api-prod` |

### Version Constraints
```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
}
```

---

## Tagging

These 6 tags are **always present** on every resource. Callers cannot remove them.

| Tag Key | Source |
|---|---|
| `project` | `var.project_name` |
| `environment` | `var.environment` |
| `owner` | `var.owner` (validated email) |
| `team` | `var.team` |
| `cost_center` | `var.cost_center` (validated `CC-XXXX`) |
| `managed_by` | hardcoded `"terraform"` |

The AWS module enforces a plan-time check that the total tag count (base + additional) does not exceed 50, which is the AWS resource tag limit.

---

## Key Design Patterns

| Pattern | Detail |
|---|---|
| **Root module = governance only** | No cloud resources at root. All infra is in child modules. |
| **Conditional NAT (AWS)** | `count = var.enable_nat_gateway ? 1 : 0` — enables or disables `aws_eip` and `aws_nat_gateway`. |
| **Dynamic multi-AZ spread (AWS)** | `element(az_names, count.index % length(az_names))` distributes subnets across AZs without hardcoding region-specific AZ names. |
| **Data source for Azure RG** | Azure module reads (never creates) the Resource Group; prevents accidental RG deletion. |
| **Plan-time tag policy (AWS)** | `terraform_data` resource with a lifecycle `precondition` fails the plan if tag count > 50, giving immediate feedback before any apply. |
| **No provider/backend blocks in modules** | Correct Terraform module practice; callers configure their own provider and backend. |
| **No tracked `.tfvars`** | Excluded by `.gitignore`; prevents secrets from entering version control. |

---

## Provider and Terraform Version Summary

| Scope | Terraform | AWS Provider | AzureRM Provider |
|---|---|---|---|
| Root module | `>= 1.5.0` | — | — |
| `modules/aws` | `>= 1.5.0` | `~> 5.0` | — |
| `modules/azure` | `>= 1.5.0` | — | `~> 3.0` |

The `>= 1.5.0` minimum is intentional: Terraform 1.5 introduced `check` blocks and expanded `lifecycle` precondition/postcondition support used by this module.

---

## Known Limitations

- **No remote backend** — no `backend` block anywhere; callers configure their own.
- **Single NAT Gateway** (AWS) — placed only in `public[0]`; not HA across multiple AZs. For production, consider one NAT GW per AZ.
- **No Azure NAT Gateway** — Azure private subnet outbound internet access is not provisioned.
- **No GCP module** — only AWS and Azure are implemented.
- **`cost_center` validation gap** — the `CC-XXXX` format validation exists only in the root module `variables.tf`. Child modules re-declare `cost_center` without repeating that validation block, so it is only enforced when the root module is called (which it always is in normal usage).
- **Azure: no NAT toggle** — unlike the AWS module, there is no `enable_nat_gateway` equivalent for Azure.
