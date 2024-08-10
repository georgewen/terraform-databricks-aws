# Given: VPC, subnets,  S3 bucket
# creates: security group,, subnet for VPC endpoints, VPC endpoints, metastore
# TODO: create new VPC, IAM Role, Security group


resource "databricks_mws_storage_configurations" "this" {
  provider                   = databricks.mws
  account_id                 = var.databricks_account_id
  bucket_name                = var.root_bucket_name
  storage_configuration_name = "${local.prefix}-storage"
}

resource "databricks_mws_credentials" "this" {
  provider         = databricks.mws
 # account_id       = var.databricks_account_id
  role_arn         = var.cross_account_arn
  credentials_name = "${local.prefix}-credentials"
}

data "aws_vpc" "prod" {
  id = var.vpc_id
}

// this subnet houses the data plane VPC endpoints
resource "aws_subnet" "dataplane_vpce" {
  vpc_id     = var.vpc_id
  cidr_block = var.vpce_subnet_cidr

  tags = merge(data.aws_vpc.prod.tags, {
    Name = "${local.prefix}-${data.aws_vpc.prod.id}-pl-vpce"
  })
}

resource "aws_route_table" "this" {
  vpc_id = var.vpc_id

  tags = merge(data.aws_vpc.prod.tags, {
    Name = "${local.prefix}-${data.aws_vpc.prod.id}-pl-local-route-tbl"
  })
}

resource "aws_route_table_association" "dataplane_vpce_rtb" {
  subnet_id      = aws_subnet.dataplane_vpce.id
  route_table_id = aws_route_table.this.id
}

data "aws_subnet" "ws_vpc_subnets" {
  for_each = toset(var.subnet_ids)
  id       = each.value
}

locals {
  vpc_cidr_blocks = [
    for subnet in data.aws_subnet.ws_vpc_subnets :
    subnet.cidr_block
  ]
}

resource "aws_security_group" "dataplane_vpce" {
  name        = "Data Plane VPC endpoint security group"
  description = "Security group shared with relay and workspace endpoints"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = toset([
      443,
      2443, # FIPS port for CSP
      6666,
    ])

    content {
      description = "Inbound rules"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = concat([var.vpce_subnet_cidr], local.vpc_cidr_blocks)
    }
  }

  dynamic "egress" {
    for_each = toset([
      443,
      2443, # FIPS port for CSP
      6666,
    ])

    content {
      description = "Outbound rules"
      from_port   = egress.value
      to_port     = egress.value
      protocol    = "tcp"
      cidr_blocks = concat([var.vpce_subnet_cidr], local.vpc_cidr_blocks)
    }
  }

  tags = merge(data.aws_vpc.prod.tags, {
    Name = "${local.prefix}-${data.aws_vpc.prod.id}-pl-vpce-sg-rules"
  })
}

resource "aws_vpc_endpoint" "backend_rest" {
  vpc_id              = var.vpc_id
  service_name        = var.workspace_vpce_service
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.dataplane_vpce.id]
  subnet_ids          = [aws_subnet.dataplane_vpce.id]
  private_dns_enabled = var.private_dns_enabled
  depends_on          = [aws_subnet.dataplane_vpce]
}

resource "aws_vpc_endpoint" "relay" {
  vpc_id              = var.vpc_id
  service_name        = var.relay_vpce_service
  vpc_endpoint_type   = "Interface"
  security_group_ids  = [aws_security_group.dataplane_vpce.id]
  subnet_ids          = [aws_subnet.dataplane_vpce.id]
  private_dns_enabled = var.private_dns_enabled
  depends_on          = [aws_subnet.dataplane_vpce]
}

resource "databricks_mws_vpc_endpoint" "backend_rest_vpce" {
  provider            = databricks.mws
  account_id          = var.databricks_account_id
  aws_vpc_endpoint_id = aws_vpc_endpoint.backend_rest.id
  vpc_endpoint_name   = "${local.prefix}-vpc-backend-${var.vpc_id}"
  region              = var.region
  depends_on          = [aws_vpc_endpoint.backend_rest]
}

resource "databricks_mws_vpc_endpoint" "relay" {
  provider            = databricks.mws
  account_id          = var.databricks_account_id
  aws_vpc_endpoint_id = aws_vpc_endpoint.relay.id
  vpc_endpoint_name   = "${local.prefix}-vpc-relay-${var.vpc_id}"
  region              = var.region
  depends_on          = [aws_vpc_endpoint.relay]
}

resource "databricks_mws_networks" "this" {
  provider           = databricks.mws
  account_id         = var.databricks_account_id
  network_name       = "${local.prefix}-network"
  security_group_ids = [var.security_group_id]
  subnet_ids         = var.subnet_ids
  vpc_id             = var.vpc_id
  vpc_endpoints {
    dataplane_relay = [databricks_mws_vpc_endpoint.relay.vpc_endpoint_id]
    rest_api        = [databricks_mws_vpc_endpoint.backend_rest_vpce.vpc_endpoint_id]
  }
}

resource "databricks_mws_private_access_settings" "pas" {
  provider                     = databricks.mws
  #account_id                   = var.databricks_account_id
  private_access_settings_name = "Private Access Settings for ${local.prefix}"
  region                       = var.region
  public_access_enabled        = true
}

resource "databricks_mws_workspaces" "this" {
  provider                   = databricks.mws
  account_id                 = var.databricks_account_id
  aws_region                 = var.region
  workspace_name             = local.prefix
  credentials_id             = databricks_mws_credentials.this.credentials_id
  storage_configuration_id   = databricks_mws_storage_configurations.this.storage_configuration_id
  network_id                 = databricks_mws_networks.this.network_id
  private_access_settings_id = databricks_mws_private_access_settings.pas.private_access_settings_id
  pricing_tier               = "ENTERPRISE"
  depends_on                 = [databricks_mws_networks.this]
}

# resource "databricks_group" "admin_group" {
#   provider     = databricks.mws
#   display_name = var.unity_admin_group
# }
# resource "databricks_metastore" "this" {
#   name          = "primary"
#   #storage_root  = "s3://${aws_s3_bucket.metastore.id}/metastore"
#   owner         = var.unity_admin_group
#   region        = var.region
#   force_destroy = true
# }

resource "databricks_metastore_assignment" "default_metastore" {
  provider             = databricks.mws
  metastore_id         = var.metastore_id
  #metastore_id         = databricks_metastore.this.id
  workspace_id = databricks_mws_workspaces.this.workspace_id
  default_catalog_name = "hive_metastore"
}