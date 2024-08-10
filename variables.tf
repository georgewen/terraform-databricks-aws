variable "databricks_account_id" {}
variable "client_id" {}
variable "client_secret" {}
variable "root_bucket_name" {}
variable "cross_account_arn" {}
variable "vpc_id" {}
variable "region" {}
variable "security_group_id" {}
variable "subnet_ids" { type = list(string) }
variable "workspace_vpce_service" {}
variable "relay_vpce_service" {}
variable "vpce_subnet_cidr" {}
variable "private_dns_enabled" { default = true }
variable "tags" { default = {} }
variable "metastore_id" {}
variable "unity_admin_group" {}

locals {
  prefix = "private-link-ws"
}