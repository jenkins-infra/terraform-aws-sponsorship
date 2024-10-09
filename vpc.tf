module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.13.0"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16" # cannot be less then /16 (more ips)


  # dual stack https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/v5.13.0/examples/ipv6-dualstack/main.tf
  enable_ipv6                                   = true
  public_subnet_assign_ipv6_address_on_creation = true

  manage_default_network_acl    = false
  map_public_ip_on_launch       = true
  manage_default_route_table    = false
  manage_default_security_group = false

  # only one zone, no need for multiple availability zones
  azs = [local.region]

  # only private subnets for security (to control allowed outbound connections)
  private_subnets = [ # only one zone
    # first VM ci.jenkins.io
    "10.0.1.0/24", # 10.0.1.1 -> 10.0.1.254 (254 ips)
    # second for VM agent jenkins
    "10.0.2.0/23", # 10.0.2.1 -> 10.0.3.254 (510 ips)
    # next for eks agents
    "10.0.4.0/23", # 10.0.4.1 -> 10.0.5.254 (510 ips)
  ]
  public_subnets = [ # need at least one for the module (line 1085 : subnet_id = element(aws_subnet.public[*].id,var.single_nat_gateway ? 0 : count.index,))
    #fake one
    "10.0.255.0/24", # 10.0.255.1 -> 10.0.255.254 (254 ips)
  ]

  ## TODO analyse result
  public_subnet_ipv6_prefixes  = [0]
  private_subnet_ipv6_prefixes = [3, 4, 5]

  # One NAT gateway per subnet (default)
  # ref. https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest#one-nat-gateway-per-subnet-default
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = false
  ###### I cannot find a way to set a multiple IP for outgoing GW ... the count is not working
  ###### https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest#external-nat-gateway-ips
  ######
  ######  https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway
  ######
  reuse_nat_ips       = true             # <= Skip creation of EIPs for the NAT Gateways
  external_nat_ip_ids = aws_eip.nat.*.id # <= IPs specified here as input to the module
  ###### I may have to create those aws_eip with name nat manually

  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

}
