module "base" {
  source = "../../"

  project_name    = var.project_name
  environment     = var.environment
  owner           = var.owner
  team            = var.team
  cost_center     = var.cost_center
  additional_tags = var.additional_tags
}

# ─── Validaciones ─────────────────────────────────────────────────────────────

resource "terraform_data" "aws_tag_validation" {
  lifecycle {
    precondition {
      condition     = length(module.base.tags) <= 50
      error_message = "AWS allows a maximum of 50 tags. Currently: ${length(module.base.tags)}."
    }
  }
}

# ─── Networking ───────────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_names = data.aws_availability_zones.available.names
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(module.base.tags, { Name = "${module.base.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(module.base.tags, { Name = "${module.base.name_prefix}-igw" })
}

# Subnets públicas — internet-facing (endpoints, ALBs)
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.az_names[count.index % length(local.az_names)]
  map_public_ip_on_launch = true

  tags = merge(module.base.tags, {
    Name = "${module.base.name_prefix}-public-${count.index + 1}"
    Type = "public"
  })
}

# Subnets privadas — comunicación inter-servicio
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.az_names[count.index % length(local.az_names)]

  tags = merge(module.base.tags, {
    Name = "${module.base.name_prefix}-private-${count.index + 1}"
    Type = "private"
  })
}

# EIP + NAT Gateway en la primera subnet pública
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(module.base.tags, { Name = "${module.base.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(module.base.tags, { Name = "${module.base.name_prefix}-nat" })
  depends_on    = [aws_internet_gateway.main]
}

# Route table pública → Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(module.base.tags, { Name = "${module.base.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[0].id
    }
  }

  tags = merge(module.base.tags, { Name = "${module.base.name_prefix}-rt-private" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}