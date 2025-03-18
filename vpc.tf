####################################################################################
# VPC / Network ('non security) resources
####################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "aws-sponso-vpc"
  cidr = local.vpc_cidr

  # dual stack https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/v5.13.0/examples/ipv6-dualstack/main.tf
  enable_ipv6                                                   = true
  public_subnet_assign_ipv6_address_on_creation                 = true
  private_subnet_assign_ipv6_address_on_creation                = false
  private_subnet_ipv6_native                                    = false
  private_subnet_enable_dns64                                   = false
  private_subnet_enable_resource_name_dns_aaaa_record_on_launch = false

  manage_default_network_acl    = false
  map_public_ip_on_launch       = true
  manage_default_route_table    = false
  manage_default_security_group = false

  azs = [for subnet_index, subnet_data in local.vpc_private_subnets : subnet_data.az]

  private_subnets      = [for subnet in local.vpc_private_subnets : subnet.cidr]
  private_subnet_names = [for subnet in local.vpc_private_subnets : subnet.name]
  private_subnet_tags  = local.common_tags

  create_private_nat_gateway_route = true

  public_subnets      = [for subnet in local.vpc_public_subnets : subnet.cidr]
  public_subnet_names = [for subnet in local.vpc_public_subnets : subnet.name]
  public_subnet_tags  = local.common_tags

  public_subnet_ipv6_prefixes = range(length(local.vpc_public_subnets))

  # One NAT gateway per subnet (default)
  # ref. https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest#one-nat-gateway-per-subnet-default
  enable_nat_gateway = true
  single_nat_gateway = false

  enable_dns_hostnames = true
}

################################################################################
# VPC Endpoints Module
################################################################################
module "vpc_endpoints" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  #TODO track with updatecli
  version = "5.19.0"

  vpc_id = module.vpc.vpc_id

  create_security_group      = true
  security_group_name_prefix = "${module.vpc.name}-vpc-endpoints-"
  security_group_description = "VPC endpoint security group"
  security_group_rules = {
    ingress_https = {
      description = "HTTPS from VPC"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }

  endpoints = {
    s3 = {
      service             = "s3"
      service_type        = "Gateway"
      route_table_ids     = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
      private_dns_enabled = true
      tags                = { Name = "s3-vpc-endpoint" }
    },
    ecr_api = {
      service             = "ecr.api"
      private_dns_enabled = true
      # Requires only 1 subnet per AZ
      subnet_ids = [for idx, data in { for subnet_index, subnet_data in module.vpc.private_subnet_objects : subnet_data.availability_zone => subnet_data.id... } : element(data, 0)]
      policy     = data.aws_iam_policy_document.generic_endpoint_policy.json
    },
  }

  tags = local.common_tags
}

################################################################################
# Supporting Resources
################################################################################

data "aws_iam_policy_document" "generic_endpoint_policy" {
  statement {
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpc"

      values = [module.vpc.vpc_id]
    }
  }
}
