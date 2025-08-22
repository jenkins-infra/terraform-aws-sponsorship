####################################################################################
# Network security resources (Network ACL and Security Groups)
####################################################################################

### Network ACLs
locals {
  abusive_cidrs = [
    "47.79.0.0/16",                              # Alibaba Singapore block 1 - https://github.com/jenkins-infra/helpdesk/issues/4575
    "47.82.0.0/16",                              # Alibaba Singapore block 2 - https://github.com/jenkins-infra/helpdesk/issues/4575
    "164.92.86.220/32",                          # DigitalOcean - US -  https://github.com/jenkins-infra/helpdesk/issues/4780
    "164.92.59.220/32",                          # DigitalOcean - US -  https://github.com/jenkins-infra/helpdesk/issues/4780
    "2a0e:cb01:91:c700:685f:b6cc:c3a7:a85a/128", # UK - https://www.crawl-tools.com/fr/whois-client/62d14555c2c67af6f5625987534e66ef
    "136.226.255.0/24",                          # Zscaler range in Mumbai - https://www.crawl-tools.com/fr/whois-client/62d14555c2c67af6f5625987534e66ef
    "89.110.84.123/32"                           # Holland - VDSina - https://www.crawl-tools.com/fr/whois-client/62d14555c2c67af6f5625987534e66ef
  ]
}
resource "aws_default_network_acl" "default" {
  default_network_acl_id = module.vpc.default_network_acl_id

  subnet_ids = concat(module.vpc.public_subnets, module.vpc.private_subnets)

  # Blocking abusive IPv6s
  dynamic "ingress" {
    for_each = toset([for cidr in local.abusive_cidrs : cidr if !can(cidrnetmask(cidr))])
    content {
      protocol = -1
      rule_no  = (40 + index(local.abusive_cidrs, ingress.value))
      action   = "deny"

      ipv6_cidr_block = ingress.value
      from_port       = 0
      to_port         = 0
    }
  }

  # Blocking abusive IPv4s
  dynamic "ingress" {
    for_each = toset([for cidr in local.abusive_cidrs : cidr if can(cidrnetmask(cidr))])
    content {
      protocol = -1
      rule_no  = (60 + index(local.abusive_cidrs, ingress.value))
      action   = "deny"

      cidr_block = ingress.value
      from_port  = 0
      to_port    = 0
    }
  }

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  ingress {
    protocol        = -1
    rule_no         = 101
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 0
    to_port         = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
  egress {
    protocol        = -1
    rule_no         = 101
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 0
    to_port         = 0
  }

  tags = local.common_tags
}

### Security Groups
resource "aws_security_group" "ephemeral_vm_agents" {
  name        = "ephemeral-vm-agents"
  description = "Allow inbound SSH only from ci.jenkins.io controller"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_from_cijio_controller" {
  description       = "Allow inbound SSH from ci.jenkins.io controller"
  security_group_id = aws_security_group.ephemeral_vm_agents.id
  cidr_ipv4         = "${aws_instance.ci_jenkins_io.private_ip}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_winrm_from_cijio_controller" {
  description       = "Allow WinRM from ci.jenkins.io controller"
  security_group_id = aws_security_group.ephemeral_vm_agents.id
  cidr_ipv4         = "${aws_instance.ci_jenkins_io.private_ip}/32"
  from_port         = 5985 # WinRM HTTP
  ip_protocol       = "tcp"
  to_port           = 5986 # WinRM HTTPS
}

resource "aws_vpc_security_group_ingress_rule" "allow_cifs_from_cijio_controller" {
  description       = "Allow CIFS over TCP from ci.jenkins.io controller"
  security_group_id = aws_security_group.ephemeral_vm_agents.id
  cidr_ipv4         = "${aws_instance.ci_jenkins_io.private_ip}/32"
  from_port         = 445 # CIFS over TCP
  ip_protocol       = "tcp"
  to_port           = 445 # CIFS over TCP
}

resource "aws_vpc_security_group_egress_rule" "allow_acp_from_cijio_agents" {
  for_each = toset(local.cijenkinsio_agents_2.artifact_caching_proxy.ips)

  description       = "Allow Artifact Caching Proxy (8080) from ci.jenkins.io VM agents"
  security_group_id = aws_security_group.ephemeral_vm_agents.id
  cidr_ipv4         = "${each.value}/32"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_vpc_security_group_egress_rule" "allow_dockerregistry_from_cijio_agents" {
  for_each = toset(local.cijenkinsio_agents_2.docker_registry_mirror.ips)

  description       = "Allow Docker Internal Registry from ci.jenkins.io VM agents"
  security_group_id = aws_security_group.ephemeral_vm_agents.id
  cidr_ipv4         = "${each.value}/32"
  from_port         = 5000
  ip_protocol       = "tcp"
  to_port           = 5000
}

resource "aws_vpc_security_group_egress_rule" "allow_dockerregistry2_from_cijio_agents" {
  for_each = toset(local.cijenkinsio_agents_2.docker_registry_mirror.ips)

  description       = "Allow Docker Internal Registry from ci.jenkins.io VM agents on alternate port"
  security_group_id = aws_security_group.ephemeral_vm_agents.id
  cidr_ipv4         = "${each.value}/32"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_security_group" "restricted_in_ssh" {
  name        = "restricted-in-ssh"
  description = "Allow inbound SSH only from trusted sources (admins or VPN)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_from_admins" {
  for_each = toset(local.ssh_admin_ips)

  description       = "Allow admin (or platform) IPv4 for inbound SSH"
  security_group_id = aws_security_group.restricted_in_ssh.id
  cidr_ipv4         = "${each.value}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_security_group" "unrestricted_in_http" {
  name        = "unrestricted-in-http"
  description = "Allow inbound HTTP from everywhere (public services)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_http_from_internet" {
  description       = "Allow HTTP from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}
## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_http6_from_internet" {
  description       = "Allow HTTP (IPv6) from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv6         = "::/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_https_from_internet" {
  description       = "Allow HTTPS from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}
## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_https6_from_internet" {
  description       = "Allow HTTS (IPv6) from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv6         = "::/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_security_group" "unrestricted_out_http" {
  name        = "unrestricted-out-http"
  description = "Allow outbound HTTP to everywhere (Internet access)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_http_to_internet" {
  description       = "Allow HTTP to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_http6_to_internet" {
  description       = "Allow HTTP (IPv6) to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv6   = "::/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_https_to_internet" {
  description       = "Allow HTTPS to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_https6_to_internet" {
  description       = "Allow HTTPS (IPv6) to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv6   = "::/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_hkp_to_internet" {
  description       = "Allow HKP to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 11371
  ip_protocol = "tcp"
  to_port     = 11371
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_hkp6_to_internet" {
  description       = "Allow HKP (IPv6) to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv6   = "::/0"
  from_port   = 11371
  ip_protocol = "tcp"
  to_port     = 11371
}

resource "aws_security_group" "allow_out_puppet_jenkins_io" {
  name        = "allow-out-puppet-jenkins-io"
  description = "Allow outbound Puppet (8140) to puppet.jenkins.io"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "allow_puppet_to_puppetmaster" {
  description       = "Allow Puppet protocol to the Puppet master"
  security_group_id = aws_security_group.allow_out_puppet_jenkins_io.id

  cidr_ipv4   = "${local.external_ips["puppet.jenkins.io"]}/32"
  from_port   = 8140
  ip_protocol = "tcp"
  to_port     = 8140
}

resource "aws_security_group" "ci_jenkins_io_controller" {
  name        = "ci-jenkins-io-controller"
  description = "Allow outbound HTTP to everywhere (Internet access)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "allow_ssh_out_s390x_agent" {
  description       = "Allow SSH to the the external s390x permanent agent"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = "${local.external_ips["s390x.ci.jenkins.io"]}/32"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_ldaps_out_ldap_jenkins_io" {
  description       = "Allow LDAPS to ldap.jenkins.io"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = "${local.external_ips["ldap.jenkins.io"]}/32"
  from_port   = 636
  ip_protocol = "tcp"
  to_port     = 636
}

resource "aws_vpc_security_group_egress_rule" "allow_ssh_out_private_subnets" {
  for_each = toset(module.vpc.private_subnets_cidr_blocks)

  description       = "Allow SSH to the private subnet ${each.key}"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = each.key
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_winrm_out_private_subnets" {
  for_each = toset(module.vpc.private_subnets_cidr_blocks)

  description       = "Allow WinRM to the private subnet ${each.key}"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = each.key
  from_port   = 5985 # WinRM HTTP
  ip_protocol = "tcp"
  to_port     = 5986 # WinRM HTTPS
}

resource "aws_vpc_security_group_egress_rule" "allow_cifs_out_private_subnets" {
  for_each = toset(module.vpc.private_subnets_cidr_blocks)

  description       = "Allow CIFS over TCP to the private subnet ${each.key}"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = each.key
  from_port   = 445 # CIFS over TCP
  ip_protocol = "tcp"
  to_port     = 445 # CIFS over TCP
}

resource "aws_vpc_security_group_ingress_rule" "allow_jnlp_in_private_subnets" {
  count = length(module.vpc.nat_public_ips)

  description       = "Allow inbound JNLP Jenkins Agent protocol from agents outbound IP ${module.vpc.nat_public_ips[count.index]}"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = "${module.vpc.nat_public_ips[count.index]}/32"
  from_port   = 50000
  ip_protocol = "tcp"
  to_port     = 50000
}

resource "aws_vpc_security_group_egress_rule" "allow_https_out_to_eks_privates_ips" {
  for_each = toset(local.cijenkinsio_agents_2.api-ipsv4)

  description       = "Allow HTTPS to ip ${each.key} for eks api"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = each.key
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}
