################################################################################
# EKS Cluster ci.jenkins.io agents-2 definition
################################################################################
module "cijenkinsio_agents_2" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.29.0"

  cluster_name = "cijenkinsio-agents-2"
  # Kubernetes version in format '<MINOR>.<MINOR>', as per https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  cluster_version = "1.29"
  create_iam_role = true

  # 2 AZs are mandatory for EKS https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#network-requirements-subnets
  # so 2 subnets at least (private ones)
  subnet_ids = slice(module.vpc.private_subnets, 1, 3)

  # Required to allow EKS service accounts to authenticate to AWS API through OIDC (and assume IAM roles)
  # useful for autoscaler, EKS addons and any AWS API usage
  enable_irsa = true

  # Allow the terraform CI IAM user to be co-owner of the cluster
  enable_cluster_creator_admin_permissions = true

  # Avoid using config map to specify admin accesses (decrease attack surface)
  authentication_mode = "API"

  access_entries = {
    # One access entry with a policy associated
    human_cluster_admins = {
      principal_arn = "arn:aws:iam::326712726440:role/infra-admin"
      type          = "STANDARD"

      policy_associations = {
        example = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type       = "cluster"
            namespaces = null
          }
        }
      }
    },
    ci_jenkins_io = {
      principal_arn     = aws_iam_role.ci_jenkins_io.arn
      type              = "STANDARD"
      kubernetes_groups = local.cijenkinsio_agents_2.kubernetes_groups
    }
  }

  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.cijenkinsio_agents_2.arn
    resources        = ["secrets"]
  }

  ## We only want to private access to the Control Plane except from infra.ci agents and VPN CIDRs (running outside AWS)
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = [for admin_ip in local.ssh_admin_ips : "${admin_ip}/32"]
  # Nodes and Pods require access to the Control Plane - https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html#cluster-endpoint-private
  # without needing to allow their IPs
  cluster_endpoint_private_access = true

  tags = merge(local.common_tags, {
    GithubRepo = "terraform-aws-sponsorship"
    GithubOrg  = "jenkins-infra"

    associated_service = "eks/cijenkinsio-agents-2"
  })

  vpc_id = module.vpc.vpc_id

  cluster_addons = {
    coredns = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = local.cijenkinsio_agents_2_cluster_addons_coredns_addon_version
      configuration_values = jsonencode({
        "tolerations" = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
      })
    }
    # Kube-proxy on an Amazon EKS cluster has the same compatibility and skew policy as Kubernetes
    # See https://kubernetes.io/releases/version-skew-policy/#kube-proxy
    kube-proxy = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = local.cijenkinsio_agents_2_cluster_addons_kubeProxy_addon_version
    }
    # https://github.com/aws/amazon-vpc-cni-k8s/releases
    vpc-cni = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = local.cijenkinsio_agents_2_cluster_addons_vpcCni_addon_version
    }
    ## https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/CHANGELOG.md
    aws-ebs-csi-driver = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = local.cijenkinsio_agents_2_cluster_addons_awsEbsCsiDriver_addon_version
      configuration_values = jsonencode({
        "controller" = {
          "tolerations" = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
        },
        "node" = {
          "tolerations" = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
        },
      })
      service_account_role_arn = module.cijenkinsio_agents_2_ebscsi_irsa_role.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    # This worker pool is expected to host the "technical" services such as karpenter, data cluster-agent, ACP, etc.
    applications = {
      name           = local.cijenkinsio_agents_2["system_node_pool"]["name"]
      instance_types = ["t4g.xlarge"]
      capacity_type  = "ON_DEMAND"
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type            = "AL2023_ARM_64_STANDARD"
      ami_release_version = local.cijenkinsio_agents_2_ami_release_version
      min_size            = 2
      max_size            = 3 # Usually 2 nodes, but accept 1 additional surging node
      desired_size        = 2

      subnet_ids = slice(module.vpc.private_subnets, 1, 2) # Only 1 subnet in 1 AZ (for EBS)

      labels = {
        jenkins = local.ci_jenkins_io["service_fqdn"]
        role    = local.cijenkinsio_agents_2["system_node_pool"]["name"]
      }
      taints = { for toleration_key, toleration_value in local.cijenkinsio_agents_2["system_node_pool"]["tolerations"] :
        toleration_key => {
          key    = toleration_value["key"],
          value  = toleration_value.value
          effect = local.toleration_taint_effects[toleration_value.effect]
        }
      }
    },
  }

  # Allow JNLP egress from pods to controller
  node_security_group_additional_rules = {
    egress_jenkins_jnlp = {
      description = "Allow egress to Jenkins TCP"
      protocol    = "TCP"
      from_port   = 50000
      to_port     = 50000
      type        = "egress"
      cidr_blocks = ["${aws_eip.ci_jenkins_io.public_ip}/32"]
    },
  }

  # Allow ingress from ci.jenkins.io VM
  cluster_security_group_additional_rules = {
    ingress_https_cijio = {
      description = "Allow ingress from ci.jenkins.io in https"
      protocol    = "TCP"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = ["${aws_instance.ci_jenkins_io.private_ip}/32"]
    },
  }
}

################################################################################
# EKS Cluster AWS resources for ci.jenkins.io agents-2
################################################################################
resource "aws_kms_key" "cijenkinsio_agents_2" {
  description         = "EKS Secret Encryption Key for the cluster cijenkinsio-agents-2"
  enable_key_rotation = true

  tags = merge(local.common_tags, {
    associated_service = "eks/cijenkinsio-agents-2"
  })
}
module "cijenkinsio_agents_2_ebscsi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.52.2"

  role_name             = "${module.cijenkinsio_agents_2.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true
  # Pass ARNs instead of IDs: https://github.com/terraform-aws-modules/terraform-aws-iam/issues/372
  ebs_csi_kms_cmk_ids = [aws_kms_key.cijenkinsio_agents_2.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.cijenkinsio_agents_2.oidc_provider_arn
      namespace_service_accounts = ["${local.cijenkinsio_agents_2["ebs-csi"]["namespace"]}:${local.cijenkinsio_agents_2["ebs-csi"]["serviceaccount"]}"]
    }
  }

  tags = local.common_tags
}
module "cijenkinsio_agents_2_awslb_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.52.2"

  role_name                              = "${module.cijenkinsio_agents_2.cluster_name}-awslb"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.cijenkinsio_agents_2.oidc_provider_arn
      namespace_service_accounts = ["${local.cijenkinsio_agents_2["awslb"]["namespace"]}:${local.cijenkinsio_agents_2["awslb"]["serviceaccount"]}"]
    }
  }

  tags = local.common_tags
}


################################################################################
# Karpenter Resources
# - https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/karpenter-mng/
# - https://karpenter.sh/v0.32/getting-started/getting-started-with-karpenter/
################################################################################
module "cijenkinsio_agents_2_karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.33.1"

  cluster_name          = module.cijenkinsio_agents_2.cluster_name
  enable_v1_permissions = true
  namespace             = local.cijenkinsio_agents_2["karpenter"]["namespace"]

  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.cijenkinsio_agents_2["karpenter"]["node_role_name"]
  create_pod_identity_association = false # we use IRSA

  enable_irsa                     = true
  irsa_namespace_service_accounts = ["${local.cijenkinsio_agents_2["karpenter"]["namespace"]}:${local.cijenkinsio_agents_2["karpenter"]["serviceaccount"]}"]
  irsa_oidc_provider_arn          = module.cijenkinsio_agents_2.oidc_provider_arn

  # Used to attach additional IAM policies to the Karpenter node IAM role
  # node_iam_role_additional_policies = {
  #   AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  # }

  tags = local.common_tags
}
# https://karpenter.sh/docs/troubleshooting/#missing-service-linked-role
resource "aws_iam_service_linked_role" "ec2_spot" {
  aws_service_name = "spot.amazonaws.com"
}

################################################################################
# Kubernetes resources in the EKS cluster ci.jenkins.io agents-2
# Note: provider is defined in providers.tf but requires the eks-token below
################################################################################
data "aws_eks_cluster_auth" "cijenkinsio_agents_2" {
  # Used by kubernetes/helm provider to authenticate to cluster with the AWS IAM identity (using a token)
  name = module.cijenkinsio_agents_2.cluster_name
}
# From https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/examples/kubernetes/storageclass/manifests/storageclass.yaml
resource "kubernetes_storage_class" "cijenkinsio_agents_2_ebs_csi_premium_retain" {
  provider = kubernetes.cijenkinsio_agents_2
  # We want one class per Availability Zone
  for_each = toset([for private_subnet in local.vpc_private_subnets : private_subnet.az if startswith(private_subnet.name, "eks")])

  metadata {
    name = "ebs-csi-premium-retain-${each.key}"
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Retain"
  parameters = {
    "csi.storage.k8s.io/fstype" = "xfs"
    "type"                      = "gp3"
  }
  allowed_topologies {
    match_label_expressions {
      key    = "topology.kubernetes.io/zone"
      values = [each.key]
    }
  }
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
}
## Install AWS Load Balancer Controller
resource "helm_release" "cijenkinsio_agents_2_awslb" {
  provider   = helm.cijenkinsio_agents_2
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version          = "1.11.0"
  create_namespace = true
  namespace        = local.cijenkinsio_agents_2["awslb"]["namespace"]

  values = [yamlencode({
    clusterName = module.cijenkinsio_agents_2.cluster_name,
    serviceAccount = {
      create = true,
      name   = local.cijenkinsio_agents_2["awslb"]["serviceaccount"],
      annotations = {
        "eks.amazonaws.com/role-arn" = module.cijenkinsio_agents_2_awslb_irsa_role.iam_role_arn,
      },
    },
    # We do not want to use ingress ALB class
    createIngressClassResource = false,
    nodeSelector               = module.cijenkinsio_agents_2.eks_managed_node_groups["applications"].node_group_labels,
    tolerations                = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
  })]
}
## Define admin credential to be used in jenkins-infra/kubernetes-management
module "cijenkinsio_agents_2_admin_sa" {
  providers = {
    kubernetes = kubernetes.cijenkinsio_agents_2
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = module.cijenkinsio_agents_2.cluster_name
  cluster_hostname           = module.cijenkinsio_agents_2.cluster_endpoint
  cluster_ca_certificate_b64 = module.cijenkinsio_agents_2.cluster_certificate_authority_data
}
moved {
  from = helm_release.karpenter
  to   = helm_release.cijenkinsio_agents_2_karpenter
}
resource "helm_release" "cijenkinsio_agents_2_karpenter" {
  provider         = helm.cijenkinsio_agents_2
  name             = "karpenter"
  namespace        = local.cijenkinsio_agents_2["karpenter"]["namespace"]
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.1.1"
  wait             = false

  values = [yamlencode({
    nodeSelector = module.cijenkinsio_agents_2.eks_managed_node_groups["applications"].node_group_labels,
    settings = {
      clusterName       = module.cijenkinsio_agents_2.cluster_name,
      clusterEndpoint   = module.cijenkinsio_agents_2.cluster_endpoint,
      interruptionQueue = module.cijenkinsio_agents_2_karpenter.queue_name,
    },
    serviceAccount = {
      create = true,
      name   = local.cijenkinsio_agents_2["karpenter"]["serviceaccount"],
      annotations = {
        "eks.amazonaws.com/role-arn" = module.cijenkinsio_agents_2_karpenter.iam_role_arn,
      },
    },
    tolerations = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
    webhook     = { enabled = false },
  })]
}
# Karpenter Node Pools (not EKS Node Groups: Nodes are managed by Karpenter itself)
resource "kubernetes_manifest" "cijenkinsio_agents_2_karpenter_node_pools" {
  provider = kubernetes.cijenkinsio_agents_2

  ## Disable this resource when running in terratest
  # to avoid errors such as "cannot create REST client: no client config"
  # or "The credentials configured in the provider block are not accepted by the API server. Error: Unauthorized"
  for_each = var.terratest ? {} : {
    for index, knp in local.cijenkinsio_agents_2.karpenter_node_pools : knp.name => knp
  }

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"

    metadata = {
      name = each.value.name
    }

    spec = {
      template = {
        metadata = {
          labels = each.value.nodeLabels
        }

        spec = {
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = [each.value.architecture]
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = [each.value.os]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"

              values = compact([
                # When spot is enabled, it's the first element and then fall back to on-demand
                lookup(each.value, "spot", false) ? "spot" : "",
                "on-demand"
              ])
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["c", "m", "r"]
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = ["2"]
            },
          ],
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = each.value.name
          }
          # If a Node stays up more than 48h, it has to be purged
          expireAfter = "48h"
          taints = [for taint in each.value.taints : {
            key    = taint.key,
            value  = taint.value,
            effect = taint.effect,
          }]
        }
      }
      limits = {
        cpu = 2400 # 8 vCPUS x 300 agents
      }
      disruption = {
        consolidationPolicy = "WhenEmpty" # Only consolidate empty nodes (to avoid restarting builds)
        consolidateAfter    = "1m"        # Linux Billing cycle on EC2
      }
    }
  }
}
# Karpenter Node Classes (setting up AMI, network, IAM permissions, etc.)
resource "kubernetes_manifest" "cijenkinsio_agents_2_karpenter_nodeclasses" {
  provider = kubernetes.cijenkinsio_agents_2

  ## Disable this resource when running in terratest
  # to avoid errors such as "cannot create REST client: no client config"
  # or "The credentials configured in the provider block are not accepted by the API server. Error: Unauthorized"
  for_each = var.terratest ? {} : {
    for index, knp in local.cijenkinsio_agents_2.karpenter_node_pools : knp.name => knp
  }

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"

    metadata = {
      name = each.value.name
    }

    spec = {
      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize = "300Gi"
            volumeType = "gp3"
            iops       = 3000
            encrypted  = true
          }
        }
      ]

      role = module.cijenkinsio_agents_2_karpenter.node_iam_role_name

      subnetSelectorTerms = [for subnet_id in slice(module.vpc.private_subnets, 2, 4) : { id = subnet_id }]
      securityGroupSelectorTerms = [
        {
          id = module.cijenkinsio_agents_2.node_security_group_id
        }
      ]
      amiSelectorTerms = [
        {
          # Few notes about AMI aliases (ref. karpenter and AWS EKS docs.)
          # - WindowsXXXX only has the "latest" version available
          # - Windows 2022 is our default OS choice for Windows containers nodes
          # - Amazon Linux 2023 is our default OS choice for Linux containers nodes
          alias = each.value.os == "windows" ? "windows2022@latest" : "al2023@v20241213"
        }
      ]
    }
  }
}
