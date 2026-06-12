# cloud-baseline

A multi-cloud Terraform baseline module providing standardized naming, governance tagging, and baseline networking for AWS and Azure. Designed to be consumed as a reusable module by downstream project deployments.

---

## What This Module Does

| Capability | Description |
|---|---|
| **Standardized naming** | Computes a consistent `<project_name>-<environment>` prefix used to name every cloud resource. |
| **Governance tagging** | Assembles a validated, mandatory tag map (`project`, `environment`, `owner`, `team`, `cost_center`, `managed_by`) and merges it with any caller-supplied tags. |
| **Baseline networking (AWS)** | Provisions a VPC with public/private subnets, Internet Gateway, optional NAT Gateway, and route tables. Subnets are distributed across availability zones automatically. |
| **Baseline networking (Azure)** | Provisions a VNet with public/private subnets and Network Security Groups enforcing HTTP/HTTPS access on the public tier and VNet-only access on the private tier. |

**The root module provisions no cloud resources.** It is pure logic — validation, naming, and tagging. All infrastructure is in the child modules under `modules/`.

---

## Requirements

| Dependency | Version |
|---|---|
| Terraform | `>= 1.5.0` |
| AWS Provider (`hashicorp/aws`) | `~> 5.0` (AWS module only) |
| AzureRM Provider (`hashicorp/azurerm`) | `~> 3.0` (Azure module only) |

No `provider` or `backend` blocks are defined in this module. Configure these in your calling deployment.

---

## Module Sources

```
github.com/Apex-CS/cloud-baseline/modules/aws?ref=<version>
github.com/Apex-CS/cloud-baseline/modules/azure?ref=<version>
```

---

## Usage

### AWS — Minimal

```hcl
# deployments/payments-api/main.tf

module "baseline" {
  source = "github.com/Apex-CS/cloud-baseline/modules/aws?ref=v0.1"

  project_name = "payments-api"
  environment  = "prod"
  owner        = "jdoe@example.com"
  team         = "backend"
  cost_center  = "CC-1042"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.baseline.tags
  }
}

# Use name_prefix to keep resource naming consistent
resource "aws_s3_bucket" "assets" {
  bucket = "${module.baseline.name_prefix}-assets"
}
```

### AWS — With Networking

```hcl
module "baseline" {
  source = "github.com/Apex-CS/cloud-baseline/modules/aws?ref=v0.1"

  project_name = "payments-api"
  environment  = "prod"
  owner        = "jdoe@example.com"
  team         = "backend"
  cost_center  = "CC-1042"

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]

  # Enable NAT Gateway in prod for private subnet egress; disable in dev to save cost
  enable_nat_gateway = var.environment == "prod"
}

# Application Load Balancer in the public subnet
resource "aws_lb" "api" {
  name            = "${module.baseline.name_prefix}-alb"
  subnets         = module.baseline.public_subnet_ids
  security_groups = [aws_security_group.alb.id]
}

# RDS in the private subnet
resource "aws_db_subnet_group" "main" {
  name       = "${module.baseline.name_prefix}-db-subnet-group"
  subnet_ids = module.baseline.private_subnet_ids
}

resource "aws_db_instance" "main" {
  db_subnet_group_name = aws_db_subnet_group.main.name
  # ...
}
```

### Azure — Minimal

> **Prerequisite:** The Resource Group must already exist before applying. This module reads it via a data source and does not create it.

```hcl
module "baseline" {
  source = "github.com/Apex-CS/cloud-baseline/modules/azure?ref=v0.1"

  project_name        = "payments-api"
  environment         = "prod"
  owner               = "jdoe@example.com"
  team                = "backend"
  cost_center         = "CC-1042"
  resource_group_name = "rg-payments-prod"
}

provider "azurerm" {
  features {}
}

resource "azurerm_storage_account" "main" {
  # Storage account names cannot contain hyphens
  name                     = replace("${module.baseline.name_prefix}sa", "-", "")
  resource_group_name      = module.baseline.resource_group_name
  location                 = module.baseline.location
  tags                     = module.baseline.tags
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
```

### Azure — With Networking

```hcl
module "baseline" {
  source = "github.com/Apex-CS/cloud-baseline/modules/azure?ref=v0.1"

  project_name        = "payments-api"
  environment         = "prod"
  owner               = "jdoe@example.com"
  team                = "backend"
  cost_center         = "CC-1042"
  resource_group_name = "rg-payments-prod"

  vnet_address_space    = ["10.0.0.0/16"]
  public_subnet_prefix  = "10.0.1.0/24"
  private_subnet_prefix = "10.0.10.0/24"
}

# App Service in the private subnet
resource "azurerm_linux_web_app" "api" {
  name                = "${module.baseline.name_prefix}-app"
  resource_group_name = module.baseline.resource_group_name
  location            = module.baseline.location
  tags                = module.baseline.tags
  # ...
}
```

---

## Input Variables

### Shared (required by both AWS and Azure modules)

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `project_name` | `string` | Yes | — | Project identifier. Lowercase alphanumeric and hyphens only; 3–20 characters. |
| `environment` | `string` | Yes | — | Deployment environment. Must be one of: `dev`, `qa`, `staging`, `prod`. |
| `owner` | `string` | Yes | — | Email address of the resource owner. |
| `team` | `string` | Yes | — | Team responsible for the resources. Cannot be blank. |
| `cost_center` | `string` | Yes | — | Cost center code in `CC-XXXX` format, e.g., `CC-1042`. |
| `additional_tags` | `map(string)` | No | `{}` | Extra tags merged on top of the mandatory base tags. |

### AWS-specific

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `vpc_cidr` | `string` | No | `"10.0.0.0/16"` | CIDR block for the VPC. |
| `public_subnet_cidrs` | `list(string)` | No | `["10.0.1.0/24", "10.0.2.0/24"]` | CIDRs for public subnets. Minimum 1 entry. Distributed across AZs automatically. |
| `private_subnet_cidrs` | `list(string)` | No | `["10.0.10.0/24", "10.0.20.0/24"]` | CIDRs for private subnets. Minimum 1 entry. |
| `enable_nat_gateway` | `bool` | No | `true` | Provision an EIP and NAT Gateway for private subnet internet egress. Incurs additional AWS cost. |

### Azure-specific

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `resource_group_name` | `string` | Yes | — | Name of a pre-existing Resource Group. The module reads it but does not create or destroy it. |
| `vnet_address_space` | `list(string)` | No | `["10.0.0.0/16"]` | Address space for the Virtual Network. |
| `public_subnet_prefix` | `string` | No | `"10.0.1.0/24"` | CIDR for the public subnet. |
| `private_subnet_prefix` | `string` | No | `"10.0.10.0/24"` | CIDR for the private subnet. |

---

## Outputs

### Shared (available from both modules)

| Output | Description |
|---|---|
| `name_prefix` | Standardized naming prefix, e.g., `payments-api-prod`. Use this to name additional resources consistently. |
| `tags` | Fully merged tag map. Apply to all resources in your deployment. |

### AWS module outputs

| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `vpc_cidr` | VPC CIDR block |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `internet_gateway_id` | Internet Gateway ID |
| `nat_gateway_id` | NAT Gateway ID, or `null` when `enable_nat_gateway = false` |

### Azure module outputs

| Output | Description |
|---|---|
| `resource_group_name` | Resource Group name |
| `resource_group_id` | Resource Group ARM ID |
| `location` | Azure region, inherited from the Resource Group |
| `vnet_id` | Virtual Network ARM ID |
| `vnet_name` | Virtual Network name |
| `public_subnet_id` | Public subnet ARM ID |
| `private_subnet_id` | Private subnet ARM ID |

---

## Tagging

The following tags are **always applied** to every resource and cannot be removed by callers:

| Tag | Value |
|---|---|
| `project` | `var.project_name` |
| `environment` | `var.environment` |
| `owner` | `var.owner` |
| `team` | `var.team` |
| `cost_center` | `var.cost_center` |
| `managed_by` | `"terraform"` (hardcoded) |

Use `additional_tags` to append extra tags without overriding these. The AWS module will fail at plan time if the total tag count exceeds 50 (the AWS resource tag limit).

---

## Naming Conventions

### AWS

Resources are named `<name_prefix>-<type>`:

| Resource | Example |
|---|---|
| VPC | `payments-api-prod-vpc` |
| Public subnet | `payments-api-prod-public-1` |
| Private subnet | `payments-api-prod-private-1` |
| Internet Gateway | `payments-api-prod-igw` |
| NAT Gateway | `payments-api-prod-nat` |

### Azure

Resources follow [Microsoft CAF abbreviation prefixes](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations):

| Resource | Example |
|---|---|
| Virtual Network | `vnet-payments-api-prod` |
| Public subnet | `snet-public-payments-api-prod` |
| Private subnet | `snet-private-payments-api-prod` |
| Public NSG | `nsg-public-payments-api-prod` |
| Private NSG | `nsg-private-payments-api-prod` |

---

## Architecture

```
Downstream caller
  └── modules/aws  OR  modules/azure
        └── module "base" { source = "../../" }   ← root module (naming + tagging only)
```

The root module is called internally by each cloud child module. It validates all governance inputs and exposes `name_prefix` and `tags`. Cloud resources are created exclusively in the child modules.

### AWS network topology

```
VPC (10.0.0.0/16)
├── Public Subnets (one per CIDR, distributed across AZs)
│   ├── map_public_ip_on_launch = true
│   └── Route: 0.0.0.0/0 → Internet Gateway
├── Private Subnets (one per CIDR, distributed across AZs)
│   └── Route: 0.0.0.0/0 → NAT Gateway  (when enable_nat_gateway = true)
│                          no default route (when enable_nat_gateway = false)
├── Internet Gateway
└── NAT Gateway (optional, placed in public[0])
```

### Azure network topology

```
Virtual Network
├── Public Subnet
│   └── NSG: allow inbound TCP 80, TCP 443
└── Private Subnet
    └── NSG: allow inbound from VirtualNetwork; deny inbound from Internet
```

> Note: Azure private subnet outbound internet access is not provisioned by this module. Add an Azure NAT Gateway or route table in your deployment if egress is required.

---

## Known Limitations

- **Single NAT Gateway (AWS)** — NAT is placed only in `public[0]`. For full high availability, provision one NAT Gateway per AZ in your deployment.
- **No Azure NAT Gateway** — private subnet internet egress is not configured.
- **No GCP module** — only AWS and Azure are implemented.
- **No remote backend** — configure your own `backend` block in the calling deployment.
