####################################################################################
# VPC / Network ('non security) resources
####################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

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
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "5.21.0"

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
      tags                = { Name = "com.amazonaws.${local.region}.s3" }
    },
    ecr_dkr = {
      service             = "ecr.dkr"
      service_type        = "Interface"
      private_dns_enabled = true
      # Only 1 subnet per AZ. ACP covers all of our AZs.
      subnet_ids = local.cijenkinsio_agents_2.artifact_caching_proxy.subnet_ids
      tags       = { Name = "com.amazonaws.${local.region}.ecr.dkr" }
    },
    ecr_api = {
      service             = "ecr.api"
      service_type        = "Interface"
      private_dns_enabled = true
      # Only 1 subnet per AZ. ACP covers all of our AZs.
      subnet_ids = local.cijenkinsio_agents_2.artifact_caching_proxy.subnet_ids,
      tags       = { Name = "com.amazonaws.${local.region}.ecr.api" }
    }
  }

  tags = local.common_tags
}
