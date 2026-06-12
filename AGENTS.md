# AGENTS.md — cloud-baseline Terraform Module

This file provides AI coding agents with a complete reference for this repository.

---

## Overview

`cloud-baseline` is a **multi-cloud Terraform baseline library** designed to be consumed as a reusable module by downstream project deployments. It provides:

1. **Standardized naming** — a consistent `<project_name>-<environment>` prefix for all resources.
2. **Standardized tagging / labeling** — a validated, mandatory tag map with governance fields that flows to all cloud resources.
3. **Baseline networking** — cloud-specific child modules provision a production-ready VPC/VNet with public and private subnets, routing, and security controls.

This module provisions **no resources at the root level**. The root module is pure logic (validation, naming, tagging). Cloud infrastructure is provisioned through the child modules under `modules/`.

---

## Repository Structure

```
cloud-baseline/
├── locals.tf                  # Shared locals: name_prefix and merged tags
├── outputs.tf                 # Root outputs: name_prefix and tags
├── variables.tf               # Root inputs: project metadata + governance fields
├── versions.tf                # Terraform version constraint (>= 1.5.0)
├── README.md
└── modules/
    ├── aws/
    │   ├── main.tf            # AWS VPC, subnets, IGW, NAT GW, route tables
    │   ├── outputs.tf         # AWS networking outputs
    │   ├── variables.tf       # AWS-specific + inherited base variables
    │   └── versions.tf        # Terraform >= 1.5.0, AWS provider ~> 5.0
    └── azure/
        ├── main.tf            # Azure VNet, subnets, NSGs, NSG associations
        ├── outputs.tf         # Azure networking outputs
        ├── variables.tf       # Azure-specific + inherited base variables
        └── versions.tf        # Terraform >= 1.5.0, AzureRM provider ~> 3.0
```

---

## Architecture

The module uses a three-tier composition pattern:

```
Downstream caller
  └── modules/aws  OR  modules/azure   (cloud-specific child module)
        └── module "base" (../../)     (root module: naming + tagging only)
```

Cloud child modules call the root module as `module "base"` to obtain `name_prefix` and `tags`, then use those to name and tag every resource they create.

---

## Root Module

### Purpose

Validates inputs, computes the naming prefix and tag map. Provisions no cloud resources.

### Inputs (`variables.tf`)

| Variable | Type | Required | Default | Validation |
|---|---|---|---|---|
| `project_name` | `string` | Yes | — | Regex `^[a-z0-9-]+$`, length 3–20 |
| `environment` | `string` | Yes | — | One of: `dev`, `qa`, `staging`, `prod` |
| `owner` | `string` | Yes | — | Valid email address format |
| `team` | `string` | Yes | — | Non-empty, non-whitespace |
| `cost_center` | `string` | Yes | — | Regex `^CC-[0-9]{4}$` (e.g., `CC-1234`) |
| `additional_tags` | `map(string)` | No | `{}` | Merged on top of base tags |

### Key Locals (`locals.tf`)

| Local | Value |
|---|---|
| `name_prefix` | `"${var.project_name}-${var.environment}"` |
| `base_tags` | Map of 6 governance tags (see Tagging section) |
| `tags` | `merge(local.base_tags, var.additional_tags)` |

### Outputs (`outputs.tf`)

| Output | Description |
|---|---|
| `name_prefix` | Naming prefix for resources, e.g., `payments-api-prod` |
| `tags` | Fully merged tag map ready to apply to cloud resources |

---

## `modules/aws` — AWS Networking

### Resources Provisioned

| Resource | Type | Notes |
|---|---|---|
| `aws_vpc.main` | VPC | DNS hostnames and support enabled |
| `aws_internet_gateway.main` | Internet Gateway | Attached to VPC |
| `aws_subnet.public[*]` | Public Subnets | One per CIDR; `map_public_ip_on_launch = true`; round-robin across AZs |
| `aws_subnet.private[*]` | Private Subnets | One per CIDR; no public IPs; round-robin across AZs |
| `aws_eip.nat[0]` | Elastic IP | Only when `enable_nat_gateway = true` |
| `aws_nat_gateway.main[0]` | NAT Gateway | Only when `enable_nat_gateway = true`; placed in `public[0]` |
| `aws_route_table.public` | Public Route Table | `0.0.0.0/0` → IGW |
| `aws_route_table.private` | Private Route Table | `0.0.0.0/0` → NAT GW (conditional); no default route if NAT disabled |
| `aws_route_table_association.public[*]` | RT Associations | All public subnets |
| `aws_route_table_association.private[*]` | RT Associations | All private subnets |
| `terraform_data.aws_tag_validation` | Meta-resource | Plan-time precondition enforcing AWS 50-tag limit |

**Data sources:**
- `data.aws_availability_zones.available` — discovers available AZs dynamically; subnets distribute across them via `count.index % length(az_names)`.

### Inputs (`variables.tf`)

**Inherited (re-declared, no extra validation):**

| Variable | Type | Required |
|---|---|---|
| `project_name` | `string` | Yes |
| `environment` | `string` | Yes |
| `owner` | `string` | Yes |
| `team` | `string` | Yes |
| `cost_center` | `string` | Yes |
| `additional_tags` | `map(string)` | No |

**AWS-specific:**

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `vpc_cidr` | `string` | No | `"10.0.0.0/16"` | VPC CIDR block; validated with `cidrhost()` |
| `public_subnet_cidrs` | `list(string)` | No | `["10.0.1.0/24", "10.0.2.0/24"]` | At least 1 required |
| `private_subnet_cidrs` | `list(string)` | No | `["10.0.10.0/24", "10.0.20.0/24"]` | At least 1 required |
| `enable_nat_gateway` | `bool` | No | `true` | Provisions EIP + NAT GW; incurs additional cost |

### Outputs (`outputs.tf`)

| Output | Description |
|---|---|
| `name_prefix` | Standardized naming prefix |
| `tags` | Full merged tag map |
| `vpc_id` | VPC ID |
| `vpc_cidr` | VPC CIDR block |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `internet_gateway_id` | Internet Gateway ID |
| `nat_gateway_id` | NAT Gateway ID, or `null` if disabled |

### Naming Convention

All resources: `"${module.base.name_prefix}-<suffix>"`, e.g.:
- VPC: `payments-api-prod-vpc`
- Subnets: `payments-api-prod-public-1`, `payments-api-prod-private-1`

---

## `modules/azure` — Azure Networking

### Prerequisites

The Azure module requires a **pre-existing Resource Group**. It reads the RG via a data source and does not create or manage it.

### Resources Provisioned

| Resource | Type | Notes |
|---|---|---|
| `azurerm_virtual_network.main` | Virtual Network | Configurable address space |
| `azurerm_subnet.public` | Public Subnet | Single CIDR |
| `azurerm_subnet.private` | Private Subnet | Single CIDR |
| `azurerm_network_security_group.public` | Public NSG | Allow HTTP:80, HTTPS:443 inbound |
| `azurerm_network_security_group.private` | Private NSG | Allow `VirtualNetwork` inbound; deny `Internet` inbound |
| `azurerm_subnet_network_security_group_association.public` | NSG Association | Binds public NSG to public subnet |
| `azurerm_subnet_network_security_group_association.private` | NSG Association | Binds private NSG to private subnet |

**Data sources:**
- `data.azurerm_resource_group.main` — reads the pre-existing RG for `location`, `name`, and `id`.

### NSG Rules

| NSG | Rule | Priority | Direction | Protocol | Port | Source | Action |
|---|---|---|---|---|---|---|---|
| Public | `allow-http` | 100 | Inbound | TCP | 80 | `*` | Allow |
| Public | `allow-https` | 110 | Inbound | TCP | 443 | `*` | Allow |
| Private | `allow-vnet-inbound` | 100 | Inbound | `*` | `*` | `VirtualNetwork` | Allow |
| Private | `deny-internet-inbound` | 200 | Inbound | `*` | `*` | `Internet` | Deny |

### Inputs (`variables.tf`)

**Inherited (re-declared):**

| Variable | Type | Required |
|---|---|---|
| `project_name` | `string` | Yes |
| `environment` | `string` | Yes |
| `owner` | `string` | Yes |
| `team` | `string` | Yes |
| `cost_center` | `string` | Yes |
| `additional_tags` | `map(string)` | No |

**Azure-specific:**

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `resource_group_name` | `string` | Yes | — | Name of a pre-existing Resource Group |
| `vnet_address_space` | `list(string)` | No | `["10.0.0.0/16"]` | VNet address space |
| `public_subnet_prefix` | `string` | No | `"10.0.1.0/24"` | Public subnet CIDR; validated with `cidrhost()` |
| `private_subnet_prefix` | `string` | No | `"10.0.10.0/24"` | Private subnet CIDR; validated with `cidrhost()` |

### Outputs (`outputs.tf`)

| Output | Description |
|---|---|
| `name_prefix` | Standardized naming prefix |
| `tags` | Full merged tag/label map |
| `resource_group_name` | Resource Group name (as resolved) |
| `resource_group_id` | Resource Group ARM ID |
| `location` | Azure region (inherited from RG) |
| `vnet_id` | Virtual Network ARM ID |
| `vnet_name` | Virtual Network name |
| `public_subnet_id` | Public subnet ARM ID |
| `private_subnet_id` | Private subnet ARM ID |

### Naming Convention

All resources follow Microsoft CAF abbreviation prefixes:
- VNet: `vnet-<name_prefix>` e.g., `vnet-payments-api-prod`
- Subnets: `snet-public-<name_prefix>` / `snet-private-<name_prefix>`
- NSGs: `nsg-public-<name_prefix>` / `nsg-private-<name_prefix>`

---

## Tagging

The following 6 tags are **always applied** to every tagged resource and cannot be removed by callers:

| Tag Key | Value Source |
|---|---|
| `project` | `var.project_name` |
| `environment` | `var.environment` |
| `owner` | `var.owner` |
| `team` | `var.team` |
| `cost_center` | `var.cost_center` |
| `managed_by` | hardcoded `"terraform"` |

Additional tags are merged via `var.additional_tags`. The AWS module enforces a plan-time precondition that the total tag count does not exceed 50 (AWS limit).

---

## Provider and Version Requirements

| Scope | Terraform | AWS Provider | AzureRM Provider |
|---|---|---|---|
| Root module | `>= 1.5.0` | — | — |
| `modules/aws` | `>= 1.5.0` | `~> 5.0` | — |
| `modules/azure` | `>= 1.5.0` | — | `~> 3.0` |

No `provider` or `backend` blocks exist in any module. These must be configured by the caller.

---

## Key Design Patterns

- **No resources in root module** — root module is governance-only (naming + tagging). Cloud resources live exclusively in child modules.
- **Conditional resources** — `enable_nat_gateway` uses `count = var.enable_nat_gateway ? 1 : 0` for optional NAT.
- **Dynamic multi-AZ distribution** (AWS) — subnets are distributed across all available AZs via `count.index % length(az_names)`, making the module region-agnostic.
- **Data source for Azure RG** — the Azure module reads (not creates) the Resource Group, preventing accidental deletion of shared infrastructure.
- **Plan-time policy enforcement** — `terraform_data` lifecycle precondition checks the 50-tag AWS limit at plan time, not runtime.
- **No `.tfvars` files tracked** — excluded by `.gitignore` for security; callers supply values through their own means.

---

## Known Limitations

- No remote backend configuration — callers must provide their own `backend` block.
- AWS NAT Gateway uses a single instance in `public[0]`; not HA across multiple AZs.
- No Azure NAT Gateway — private subnet outbound internet access is not provisioned for Azure.
- No GCP module — only AWS and Azure are implemented.
- `cost_center` format validation (`CC-XXXX`) exists only in the root module; child modules re-declare the variable without this validation.
