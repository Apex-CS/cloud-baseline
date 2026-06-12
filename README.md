# How to deploy using modules

## Base configuration

### AWS
```hcl
# deployments/payments-api/main.tf

module "baseline" {
  source  = "app.terraform.io/<ORG>/baseline/multicloud//modules/aws"
  version = "~> 1.0"

  project_name = "payments-api"
  environment  = "prod"
  owner        = "jdoe@apexsystems.com"
  team         = "backend"
  cost_center  = "innovation-center"
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.baseline.tags
  }
}

resource "aws_s3_bucket" "assets" {
  # name_prefix can be used to keep consistency in naming.
  bucket = "${module.baseline.name_prefix}-assets"
}
```

### Azure

```hcl
module "baseline" {
  source  = "app.terraform.io/<ORG>/baseline/multicloud//modules/azure"
  version = "~> 1.0"

  project_name = "payments-api"
  environment  = "prod"
  owner        = "jdoe@apexsystems.com"
  team         = "backend"
  cost_center  = "innovation-center"
  location     = "eastus"
}

resource "azurerm_storage_account" "main" {
  name                = replace("${module.baseline.name_prefix}sa", "-", "")
  resource_group_name = module.baseline.resource_group_name  # del output
  location            = module.baseline.location
  tags                = module.baseline.tags

  account_tier             = "Standard"
  account_replication_type = "LRS"
}
```

## Networking

### AWS
```hcl
module "baseline" {
  source  = "app.terraform.io/<ORG>/baseline/multicloud//modules/aws"
  version = "~> 2.0"

  # ...other vars...
  enable_nat_gateway   = var.environment == "prod"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]
}

# ALB en subnet pública
resource "aws_lb" "api" {
  subnets = module.baseline.public_subnet_ids
}

# ECS/RDS en subnet privada
resource "aws_db_instance" "main" {
  db_subnet_group_name = aws_db_subnet_group.main.name
}

resource "aws_db_subnet_group" "main" {
  subnet_ids = module.baseline.private_subnet_ids
}
```

### Azure
```hcl
module "baseline" {
  source  = "app.terraform.io/<ORG>/baseline/multicloud//modules/azure"
  version = "~> 2.0"

  # ...other vars...
  resource_group_name   = "rg-payments-prod" 
  public_subnet_prefix  = "10.0.1.0/24"
  private_subnet_prefix = "10.0.10.0/24"
}

resource "azurerm_linux_web_app" "api" {
  resource_group_name = module.baseline.resource_group_name
  location            = module.baseline.location  # derivado del data source
  # ...
}
```