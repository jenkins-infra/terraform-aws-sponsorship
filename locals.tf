locals {
  aws_account_id = "326712726440"
  region         = "us-east-2"

  common_tags = {
    "scope"      = "terraform-managed"
    "repository" = "jenkins-infra/terraform-aws-sponsorship"
  }

  ci_jenkins_io = {
    service_fqdn       = "ci.jenkins.io"
    controller_vm_fqdn = "aws.ci.jenkins.io"
  }

  cijenkinsio_agents_2_cluster_addons_coredns_addon_version             = "v1.11.4-eksbuild.2"
  cijenkinsio_agents_2_cluster_addons_kubeProxy_addon_version           = "v1.29.11-eksbuild.2"
  cijenkinsio_agents_2_cluster_addons_vpcCni_addon_version              = "v1.19.2-eksbuild.1"
  cijenkinsio_agents_2_cluster_addons_eksPodIdentityAgent_addon_version = "v1.3.4-eksbuild.1"
  cijenkinsio_agents_2_cluster_addons_awsEbsCsiDriver_addon_version     = "v1.38.1-eksbuild.2"

  cijenkinsio_agents_2_ami_release_version = "1.29.10-20241213"

  cijenkinsio_agents_2 = {
    api-ipsv4 = ["10.0.131.86/32", "10.0.133.102/32"]
    karpenter = {
      node_role_name = "KarpenterNodeRole-cijenkinsio-agents-2",
      namespace      = "karpenter",
      serviceaccount = "karpenter",
    },
    awslb = {
      namespace      = "awslb"
      serviceaccount = "awslb",
    },
    ebs-csi = {
      namespace      = "kube-system",
      serviceaccount = "ebs-csi-controller-sa",
    },
    artifact_caching_proxy = {
      ips = [for subnet in local.vpc_private_subnets : cidrhost(subnet.cidr, "-8")],
    }
    kubernetes_groups = ["ci-jenkins-io"],
    system_node_pool = {
      name = "applications"
      tolerations = [
        {
          "effect" : "NoSchedule",
          "key" : "${local.ci_jenkins_io["service_fqdn"]}/applications",
          "operator" : "Equal",
          "value" : "true"
        },
      ],
    }
    karpenter_node_pools = [
      {
        name         = "agents-linux-amd64"
        os           = "linux"
        architecture = "amd64"
        spot         = true
        nodeLabels = {
          "jenkins" = "ci.jenkins.io",
          "role"    = "jenkins-agents",
        }
        taints = [
          {
            "effect" : "NoSchedule",
            "key" : "${local.ci_jenkins_io["service_fqdn"]}/agents",
            "operator" : "Equal",
            "value" : "true",
          },
        ],
      },
      {
        name         = "agents-bom-linux-amd64"
        os           = "linux"
        architecture = "amd64"
        spot         = true
        nodeLabels = {
          "jenkins" = "ci.jenkins.io",
          "role"    = "jenkins-agents-bom",
        }
        taints = [
          {
            "effect" : "NoSchedule",
            "key" : "${local.ci_jenkins_io["service_fqdn"]}/agents",
            "operator" : "Equal",
            "value" : "true"
          },
          {
            "effect" : "NoSchedule",
            "key" : "${local.ci_jenkins_io["service_fqdn"]}/bom",
            "operator" : "Equal",
            "value" : "true"
          },
        ],
      },
    ]
    subnets = ["eks-1", "eks-2"]
  }

  toleration_taint_effects = {
    "NoSchedule"       = "NO_SCHEDULE",
    "NoExecute"        = "NO_EXECUTE",
    "PreferNoSchedule" = "PREFER_NO_SCHEDULE",
  }

  #####
  ## External and outbounds IP used by resources for network restrictions.
  ## Note: we use scalar (strings with space separator) to manage type changes by updatecli's HCL parser
  ##   and a map with complex type (list or strings). Ref. https://github.com/updatecli/updatecli/issues/1859#issuecomment-1884876679
  #####
  # Tracked by 'updatecli' from the following source: https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
  outbound_ips_infracijenkinsioagents1_jenkins_io = "20.122.14.108 20.186.70.154"
  # Tracked by 'updatecli' from the following source: https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
  outbound_ips_private_vpn_jenkins_io = "172.176.126.194"
  outbound_ips = {
    # Terraform management and Docker-packaging build
    "infracijenkinsioagents1.jenkins.io" = split(" ", local.outbound_ips_infracijenkinsioagents1_jenkins_io)
    # Connections routed through the VPN
    "private.vpn.jenkins.io" = split(" ", local.outbound_ips_private_vpn_jenkins_io)
  }
  external_ips = {
    # Jenkins Puppet Master
    # TODO: automate retrieval of this IP with updatecli
    "puppet.jenkins.io" = "20.12.27.65",
    # TODO: automate retrieval of this IP with updatecli
    "ldap.jenkins.io" = "20.7.180.148",
    # TODO: automate retrieval of this IP with updatecli
    "s390x.ci.jenkins.io" = "148.100.84.76",
  }
  ssh_admin_ips = [
    for ip in flatten(concat(
      # Allow Terraform management from infra.ci agents
      local.outbound_ips["infracijenkinsioagents1.jenkins.io"],
      # Connections routed through the VPN
      local.outbound_ips["private.vpn.jenkins.io"],
    )) : ip
    if can(cidrnetmask("${ip}/32"))
  ]

  ## VPC Setup
  vpc_cidr = "10.0.0.0/16" # cannot be less then /16 (more ips)
  # Public subnets use the first partition of the vpc_cidr (index 0)
  vpc_public_subnets = [
    {
      name = "controller",
      az   = format("${local.region}%s", "b"),
      # First /23 of the first subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[0], 6, 0)
    },
    {
      name = "eks-public-1",
      az   = format("${local.region}%s", "a"),
      # First /23 of the first subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[0], 6, 1)
    },
  ]
  # Public subnets use the second partition of the vpc_cidr (index 1)
  vpc_private_subnets = [
    {
      name = "vm-agents-1",
      az   = format("${local.region}%s", "b"),
      # First /23 of the second subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[1], 6, 0)
    },
    {
      name = "eks-1",
      az   = format("${local.region}%s", "a"),
      # Second /23 of the second subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[1], 6, 1)
    },
    { name = "eks-2",
      az   = format("${local.region}%s", "c"),
      # Third /23 of the second subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[1], 6, 2)
    }
  ]
}
