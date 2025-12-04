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

  cijenkinsio_agents_2_cluster_addons_coredns_addon_version             = "v1.12.4-eksbuild.1"
  cijenkinsio_agents_2_cluster_addons_kubeProxy_addon_version           = "v1.33.5-eksbuild.2"
  cijenkinsio_agents_2_cluster_addons_vpcCni_addon_version              = "v1.20.5-eksbuild.1"
  cijenkinsio_agents_2_cluster_addons_awsEbsCsiDriver_addon_version     = "v1.53.0-eksbuild.1"
  cijenkinsio_agents_2_cluster_addons_awsS3CsiDriver_addon_version      = "v2.2.0-eksbuild.1"
  cijenkinsio_agents_2_cluster_addons_eksPodIdentityAgent_addon_version = "v1.3.10-eksbuild.1"

  cijenkinsio_agents_2_ami_release_version = "1.33.5-20251120"

  cijenkinsio_agents_2 = {
    # TODO: where does the values come from?
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
      subnet_ids = [for idx, data in { for subnet_index, subnet_data in module.vpc.private_subnet_objects : subnet_data.availability_zone => subnet_data.id... } : element(data, 0)],
      ips        = [for idx, data in { for subnet_index, subnet_data in module.vpc.private_subnet_objects : subnet_data.availability_zone => subnet_data.cidr_block... } : cidrhost(element(data, 0), "-8")],
    }
    docker_registry_mirror = {
      subnet_ids = [for idx, data in { for subnet_index, subnet_data in module.vpc.private_subnet_objects : subnet_data.availability_zone => subnet_data.id... } : element(data, 0)],
      ips        = [for idx, data in { for subnet_index, subnet_data in module.vpc.private_subnet_objects : subnet_data.availability_zone => subnet_data.cidr_block... } : cidrhost(element(data, 0), "-9")],
    }
    agent_namespaces = {
      "jenkins-agents" = {
        pods_quota = 150,
      },
      "jenkins-agents-bom" = {
        pods_quota = 150,
      },
    },
    kubernetes_groups = ["ci-jenkins-io"],
    system_node_pool = {
      name = "applications",
      tolerations = [
        {
          "effect" : "NoSchedule",
          "key" : "${local.ci_jenkins_io["service_fqdn"]}/applications",
          "operator" : "Equal",
          "value" : "true",
        },
      ],
      # Only 1 subnet in 1 AZ (for EBS)
      subnet_ids = [
        for idx, subnet in local.vpc_private_subnets : module.vpc.private_subnets[idx] if subnet.name == "eks-1"
      ]
    }
    karpenter_node_pools = [
      {
        name             = "agents-linux-amd64",
        os               = "linux",
        architecture     = "amd64",
        consolidateAfter = "1m",
        spot             = true,
        nodeLabels = {
          "jenkins" = "ci.jenkins.io",
          "role"    = "jenkins-agents",
        },
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
        name             = "agents-bom-linux-amd64",
        os               = "linux",
        architecture     = "amd64",
        consolidateAfter = "1m",
        spot             = true,
        nodeLabels = {
          "jenkins" = "ci.jenkins.io",
          "role"    = "jenkins-agents-bom",
        },
        taints = [
          {
            "effect" : "NoSchedule",
            "key" : "${local.ci_jenkins_io["service_fqdn"]}/agents",
            "operator" : "Equal",
            "value" : "true",
          },
          {
            "effect" : "NoSchedule",
            "key" : "${local.ci_jenkins_io["service_fqdn"]}/bom",
            "operator" : "Equal",
            "value" : "true",
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
  outbound_ips_infra_ci_jenkins_io = "20.57.120.46 52.179.141.53 172.210.200.59 20.10.193.4"
  # Tracked by 'updatecli' from the following source: https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
  outbound_ips_private_vpn_jenkins_io = "52.232.183.117"

  outbound_ips = {
    # Terraform management and Docker-packaging build
    "infra.ci.jenkins.io" = split(" ", local.outbound_ips_infra_ci_jenkins_io)
    # Connections routed through the VPN
    "private.vpn.jenkins.io" = split(" ", local.outbound_ips_private_vpn_jenkins_io),
  }
  external_ips = {
    # Jenkins Puppet Master
    # TODO: automate retrieval of this IP with updatecli
    "puppet.jenkins.io" = "20.12.27.65",
    # TODO: automate retrieval of this IP with updatecli
    "ldap.jenkins.io" = "20.57.70.169",
    # TODO: automate retrieval of this IP with updatecli
    "s390x.ci.jenkins.io" = "148.100.84.76",
  }
  ssh_admin_ips = [
    for ip in flatten(concat(
      # Allow Terraform management from infra.ci agents
      local.outbound_ips["infra.ci.jenkins.io"],
      # Connections routed through the VPN
      local.outbound_ips["private.vpn.jenkins.io"],
    )) : ip
    if can(cidrnetmask("${ip}/32"))
  ]

  agents_availability_zone = format("${local.region}%s", "a")

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
      az   = local.agents_availability_zone,
      # First /23 of the first subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[0], 6, 1)
    },
  ]
  # Public subnets use the second partition of the vpc_cidr (index 1)
  vpc_private_subnets = [
    {
      name = "us-east-2b",
      az   = format("${local.region}%s", "b"),
      # A /23 (the '6' integer argument) on the second subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[1], 6, 4)
    },
    {
      name = "eks-1",
      az   = local.agents_availability_zone,
      # A /23 (the '6' integer argument) on the second subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[1], 6, 1)
    },
    {
      name = "eks-2",
      az   = format("${local.region}%s", "c"),
      # A /21 (the '4' integer argument) on the second subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[1], 4, 2)
    },
    {
      name = "eks-3",
      az   = local.agents_availability_zone,
      # A /20 (the '3' integer argument) on the second subset of the VPC (split in 2)
      cidr = cidrsubnet(cidrsubnets(local.vpc_cidr, 1, 1)[1], 3, 4)
    },
  ]
}
