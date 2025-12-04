################################################################################
# EKS Cluster ci.jenkins.io agents-2 definition
################################################################################
module "cijenkinsio_agents_2" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.2.0"

  name = "cijenkinsio-agents-2"
  # Kubernetes version in format '<MINOR>.<MINOR>', as per https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  kubernetes_version = "1.33"
  create_iam_role    = true

  # 2 AZs are mandatory for EKS https://docs.aws.amazon.com/eks/latest/userguide/network-reqs.html#network-requirements-subnets
  # so 2 subnets at least (private ones)
  subnet_ids = [for idx, subnet in local.vpc_private_subnets : module.vpc.private_subnets[idx] if startswith(subnet.name, "eks")]

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
        cluster_admin = {
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
    },
  }

  create_kms_key = false
  encryption_config = {
    provider_key_arn = aws_kms_key.cijenkinsio_agents_2.arn
    resources        = ["secrets"]
  }

  ## We only want to private access to the Control Plane except from infra.ci agents and VPN CIDRs (running outside AWS)
  endpoint_public_access       = true
  endpoint_public_access_cidrs = [for admin_ip in local.ssh_admin_ips : "${admin_ip}/32"]
  # Nodes and Pods require access to the Control Plane - https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html#cluster-endpoint-private
  # without needing to allow their IPs
  endpoint_private_access = true

  tags = merge(local.common_tags, {
    GithubRepo = "terraform-aws-sponsorship"
    GithubOrg  = "jenkins-infra"

    associated_service = "eks/cijenkinsio-agents-2"
  })

  vpc_id = module.vpc.vpc_id

  addons = {
    coredns = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = local.cijenkinsio_agents_2_cluster_addons_coredns_addon_version
      configuration_values = jsonencode({
        "tolerations" = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
      })
      resolve_conflicts_on_create = "OVERWRITE"
    }
    # Kube-proxy on an Amazon EKS cluster has the same compatibility and skew policy as Kubernetes
    # See https://kubernetes.io/releases/version-skew-policy/#kube-proxy
    kube-proxy = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version               = local.cijenkinsio_agents_2_cluster_addons_kubeProxy_addon_version
      resolve_conflicts_on_create = "OVERWRITE"
    }
    # https://github.com/aws/amazon-vpc-cni-k8s/releases
    vpc-cni = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = local.cijenkinsio_agents_2_cluster_addons_vpcCni_addon_version
      # Ensure vpc-cni changes are applied before any EC2 instances are created
      before_compute = true
      configuration_values = jsonencode({
        # Allow Windows NODE, but requires access entry for node IAM profile to be of kind 'EC2_WINDOWS' to get the proper IAM permissions (otherwise DNS does not resolve on Windows pods)
        enableWindowsIpam = "true"
      })
      resolve_conflicts_on_create = "OVERWRITE"
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
      service_account_role_arn    = module.cijenkinsio_agents_2_ebscsi_irsa_role.iam_role_arn
      resolve_conflicts_on_create = "OVERWRITE"
    },
    ## https://github.com/awslabs/mountpoint-s3-csi-driver
    aws-mountpoint-s3-csi-driver = {
      addon_version = local.cijenkinsio_agents_2_cluster_addons_awsS3CsiDriver_addon_version
      # resolve_conflicts_on_create = "OVERWRITE"
      configuration_values = jsonencode({
        "node" = {
          "tolerateAllTaints" = true,
        },
      })
      service_account_role_arn    = aws_iam_role.s3_ci_jenkins_io_maven_cache.arn
      resolve_conflicts_on_create = "OVERWRITE"
    },
    eks-pod-identity-agent = {
      addon_version = local.cijenkinsio_agents_2_cluster_addons_eksPodIdentityAgent_addon_version
    },
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

      subnet_ids = local.cijenkinsio_agents_2["system_node_pool"]["subnet_ids"]

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

      metadata_options = {
        http_put_response_hop_limit = 2
      }

      monitoring = {
        enabled = true
      }

      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
        additional                         = aws_iam_policy.ecrpullthroughcache.arn
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
    ingress_hub_mirror = {
      description = "Allow ingress to Registry Pods"
      protocol    = "TCP"
      from_port   = 5000
      to_port     = 5000
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_hub_mirror_2 = {
      description = "Allow ingress to Registry Pods with alternate port"
      protocol    = "TCP"
      from_port   = 8080
      to_port     = 8080
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Allow ingress from ci.jenkins.io VM
  security_group_additional_rules = {
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
# S3 Persistent Volume Resources
################################################################################
resource "aws_s3_bucket" "ci_jenkins_io_maven_cache" {
  bucket        = "ci-jenkins-io-maven-cache"
  force_destroy = true

  tags = local.common_tags
}
resource "aws_s3_bucket_public_access_block" "ci_jenkins_io_maven_cache" {
  bucket                  = aws_s3_bucket.ci_jenkins_io_maven_cache.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_iam_policy" "s3_ci_jenkins_io_maven_cache" {
  name        = "s3-ci-jenkins-io-maven-cache"
  description = "IAM policy for S3 access to ci_jenkins_io_maven_cache S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "MountpointFullBucketAccess",
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.ci_jenkins_io_maven_cache.arn,
        ],
      },
      {
        Sid    = "MountpointFullObjectAccess",
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
        ],
        Resource = [
          "${aws_s3_bucket.ci_jenkins_io_maven_cache.arn}/*",
        ],
      },
    ],
  })
}
resource "aws_iam_role" "s3_ci_jenkins_io_maven_cache" {
  name = "s3-ci-jenkins-io-maven-cache"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = module.cijenkinsio_agents_2.oidc_provider_arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringLike = {
            "${replace(module.cijenkinsio_agents_2.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:s3-csi-*",
            "${replace(module.cijenkinsio_agents_2.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com",
          },
        },
      },
    ],
  })
}
resource "aws_iam_role_policy_attachment" "s3_role_attachment" {
  policy_arn = aws_iam_policy.s3_ci_jenkins_io_maven_cache.arn
  role       = aws_iam_role.s3_ci_jenkins_io_maven_cache.name
}

################################################################################################################################################################
## We define 3 PVCs (and associated PVs) all using the same S3 bucket:
## - 1 ReadWriteMany in a custom namespace which will be used to populate cache in a "non Jenkins agents namespace" (to avoid access through ci.jenkins.io)
## - 1 ReadOnlyMany per "Jenkins agents namespace" to allow consumption by container agents
################################################################################################################################################################
# Kubernetes Resources: PV and PVC must be statically provisioned
# Ref. https://github.com/awslabs/mountpoint-s3-csi-driver/tree/main?tab=readme-ov-file#features
resource "kubernetes_namespace" "jenkins_agents" {
  provider = kubernetes.cijenkinsio_agents_2

  for_each = local.cijenkinsio_agents_2.agent_namespaces

  metadata {
    name = each.key
    labels = {
      name = "${each.key}"
    }
  }
}
resource "kubernetes_namespace" "maven_cache" {
  provider = kubernetes.cijenkinsio_agents_2

  metadata {
    name = "maven-cache"
    labels = {
      name = "maven-cache"
    }
  }
}

### ReadOnly PVs consumed by Jenkins agents
# https://github.com/awslabs/mountpoint-s3-csi-driver/blob/main/examples/kubernetes/static_provisioning/static_provisioning.yaml
resource "kubernetes_persistent_volume" "ci_jenkins_io_maven_cache_readonly" {
  provider = kubernetes.cijenkinsio_agents_2

  for_each = local.cijenkinsio_agents_2.agent_namespaces

  metadata {
    name = format("%s-%s", aws_s3_bucket.ci_jenkins_io_maven_cache.id, lower(each.key))
  }
  spec {
    capacity = {
      storage = "1200Gi", # ignored, required
    }
    access_modes                     = ["ReadOnlyMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "" # Required for static provisioning (even if empty)
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {                                              # To ensure no other PVCs can claim this PV
      namespace = each.key                                   # Namespace is required even though it's in "default" namespace.
      name      = aws_s3_bucket.ci_jenkins_io_maven_cache.id # Name of your PVC
    }
    mount_options = [
      # Ref. https://github.com/awslabs/mountpoint-s3-csi-driver/blob/370006141669d483c1dcb01c594fe9048045edf6/pkg/mountpoint/args.go#L11-L23
      "allow-other", # Allow non root users to mount and access volume
      "gid=1001",    # Default group 'jenkins' - https://github.com/jenkins-infra/packer-images/blob/a9f913c0f5cf7baf49e370c4b823b499bf757e06/provisioning/ubuntu-provision.sh#L35
      "uid=1001",    # Default user 'jenkins' - https://github.com/jenkins-infra/packer-images/blob/a9f913c0f5cf7baf49e370c4b823b499bf757e06/provisioning/ubuntu-provision.sh#L32
    ]
    persistent_volume_source {
      csi {
        driver        = "s3.csi.aws.com"
        volume_handle = format("%s-%s", aws_s3_bucket.ci_jenkins_io_maven_cache.id, lower(each.key))
        volume_attributes = {
          bucketName = aws_s3_bucket.ci_jenkins_io_maven_cache.id
        }
      }
    }
  }
}
### ReadOnly PVCs consumed by Jenkins agents
# https://github.com/awslabs/mountpoint-s3-csi-driver/blob/main/examples/kubernetes/static_provisioning/static_provisioning.yaml
resource "kubernetes_persistent_volume_claim" "ci_jenkins_io_maven_cache_readonly" {
  provider = kubernetes.cijenkinsio_agents_2

  for_each = local.cijenkinsio_agents_2.agent_namespaces

  metadata {
    name      = aws_s3_bucket.ci_jenkins_io_maven_cache.id
    namespace = each.key
  }
  spec {
    access_modes       = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].metadata.0.name
    storage_class_name = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly[each.key].spec[0].capacity.storage
      }
    }
  }
}

### ReadWrite PV used to fill the cache
# https://github.com/awslabs/mountpoint-s3-csi-driver/blob/main/examples/kubernetes/static_provisioning/static_provisioning.yaml
resource "kubernetes_persistent_volume" "ci_jenkins_io_maven_cache_write" {
  provider = kubernetes.cijenkinsio_agents_2

  metadata {
    name = format("%s-%s", aws_s3_bucket.ci_jenkins_io_maven_cache.id, kubernetes_namespace.maven_cache.metadata[0].name)
  }
  spec {
    capacity = {
      storage = "1200Gi", # ignored, required
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "" # Required for static provisioning (even if empty)
    # Ensure that only the designated PVC can claim this PV (to avoid injection as PV are not namespaced)
    claim_ref {                                                     # To ensure no other PVCs can claim this PV
      namespace = kubernetes_namespace.maven_cache.metadata[0].name # Namespace is required even though it's in "default" namespace.
      name      = aws_s3_bucket.ci_jenkins_io_maven_cache.id        # Name of your PVC
    }
    mount_options = [
      # Ref. https://github.com/awslabs/mountpoint-s3-csi-driver/blob/370006141669d483c1dcb01c594fe9048045edf6/pkg/mountpoint/args.go#L11-L23
      "allow-delete",    # Allow removing (rm, mv, etc.) files in the S3 bucket through filesystem
      "allow-other",     # Allow non root users to mount and access volume
      "allow-overwrite", # Allow overwriting (cp, tar, etc.) files in the S3 bucket through filesystem
      "gid=1001",        # Default group 'jenkins' - https://github.com/jenkins-infra/packer-images/blob/a9f913c0f5cf7baf49e370c4b823b499bf757e06/provisioning/ubuntu-provision.sh#L35
      "uid=1001",        # Default user 'jenkins' - https://github.com/jenkins-infra/packer-images/blob/a9f913c0f5cf7baf49e370c4b823b499bf757e06/provisioning/ubuntu-provision.sh#L32
    ]
    persistent_volume_source {
      csi {
        driver        = "s3.csi.aws.com"
        volume_handle = format("%s-%s", aws_s3_bucket.ci_jenkins_io_maven_cache.id, kubernetes_namespace.maven_cache.metadata[0].name)
        volume_attributes = {
          bucketName = aws_s3_bucket.ci_jenkins_io_maven_cache.id
        }
      }
    }
  }
}
### ReadWrite PVC used to fill the cache
# https://github.com/awslabs/mountpoint-s3-csi-driver/blob/main/examples/kubernetes/static_provisioning/static_provisioning.yaml
resource "kubernetes_persistent_volume_claim" "ci_jenkins_io_maven_cache_write" {
  provider = kubernetes.cijenkinsio_agents_2

  metadata {
    name      = aws_s3_bucket.ci_jenkins_io_maven_cache.id
    namespace = kubernetes_namespace.maven_cache.metadata[0].name
  }
  spec {
    access_modes       = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.spec[0].access_modes
    volume_name        = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.metadata.0.name
    storage_class_name = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.spec[0].storage_class_name
    resources {
      requests = {
        storage = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_write.spec[0].capacity.storage
      }
    }
  }
}
################################################################################################################################################################


################################################################################################################################################################
# EKS Cluster AWS resources for ci.jenkins.io agents-2
################################################################################################################################################################
resource "aws_kms_key" "cijenkinsio_agents_2" {
  description         = "EKS Secret Encryption Key for the cluster cijenkinsio-agents-2"
  enable_key_rotation = true

  tags = merge(local.common_tags, {
    associated_service = "eks/cijenkinsio-agents-2"
  })
}
module "cijenkinsio_agents_2_ebscsi_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

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
  version = "5.58.0"

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
# - https://karpenter.sh/v1.2/getting-started/getting-started-with-karpenter/
################################################################################
module "cijenkinsio_agents_2_karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.10.1"

  # EC2_WINDOWS is a superset of EC2_LINUX to allow Windows nodes
  access_entry_type = "EC2_WINDOWS"

  cluster_name = module.cijenkinsio_agents_2.cluster_name
  namespace    = local.cijenkinsio_agents_2["karpenter"]["namespace"]

  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = local.cijenkinsio_agents_2["karpenter"]["node_role_name"]
  create_pod_identity_association = true

  node_iam_role_additional_policies = {
    AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    additional                         = aws_iam_policy.ecrpullthroughcache.arn
  }

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
  provider = helm.cijenkinsio_agents_2
  depends_on = [
    data.aws_eks_cluster_auth.cijenkinsio_agents_2,
    module.cijenkinsio_agents_2_karpenter.queue_name,
  ]
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  version          = "1.16.0"
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
resource "helm_release" "cijenkinsio_agents_2_karpenter" {
  provider         = helm.cijenkinsio_agents_2
  name             = "karpenter"
  namespace        = local.cijenkinsio_agents_2["karpenter"]["namespace"]
  create_namespace = true
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.8.2"
  wait             = false

  values = [yamlencode({
    nodeSelector = module.cijenkinsio_agents_2.eks_managed_node_groups["applications"].node_group_labels,
    settings = {
      clusterName       = module.cijenkinsio_agents_2.cluster_name,
      clusterEndpoint   = module.cijenkinsio_agents_2.cluster_endpoint,
      interruptionQueue = module.cijenkinsio_agents_2_karpenter.queue_name,
    },
    tolerations = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
    webhook     = { enabled = false },
  })]
}

## Kubernetes Manifests, which require CRD to be installed
## Note: requires 2 times a terraform apply
## Ref. https://github.com/hashicorp/terraform-provider-kubernetes/issues/2597, https://github.com/hashicorp/terraform-provider-kubernetes/issues/2673 etc.
# Karpenter Node Pools (not EKS Node Groups: Nodes are managed by Karpenter itself)
resource "kubernetes_manifest" "cijenkinsio_agents_2_karpenter_node_pools" {
  provider = kubernetes.cijenkinsio_agents_2

  depends_on = [
    # CRD are required
    helm_release.cijenkinsio_agents_2_awslb,
  ]

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
              values = [
                # Strip suffix for Windows node (which contains the OS version)
                startswith(each.value.os, "windows") ? "windows" : each.value.os,
              ]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"

              values = compact([
                lookup(each.value, "spot", false) ? "spot" : "",
                "on-demand",
              ])
            },
            {
              key      = "karpenter.k8s.aws/instance-family"
              operator = "In"
              # The specified families must provide at least a (if many: node classe specifies RAID0) local NVMe(s) to be used for container and ephemeral storage
              # Otherwise EBS volume needs to be tuned in the node class
              values = ["m6id", "m6idn", "m5d", "m5dn", "m5ad", "c6id", "c5d", "c5ad", "r6id", "r6idn", "r5d", "r5dn", "r5ad", "x2idn", "x2iedn"]
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
        cpu = 3200 # 8 vCPUS x 400 agents
      }
      disruption = {
        consolidationPolicy = "WhenEmpty" # Only consolidate empty nodes (to avoid restarting builds)
        consolidateAfter    = lookup(each.value, "consolidateAfter", "1m")
      }
    }
  }
}
# Karpenter Node Classes (setting up AMI, network, IAM permissions, etc.)
resource "kubernetes_manifest" "cijenkinsio_agents_2_karpenter_nodeclasses" {
  provider = kubernetes.cijenkinsio_agents_2
  depends_on = [
    # CRD are required
    helm_release.cijenkinsio_agents_2_awslb,
  ]

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
      instanceStorePolicy = "RAID0"
      ## Block Device and Instance Store Policy should be mutually exclusive: EBS is always used for the root device,
      ## but Amazon Linux (AL2 and AL2023) takes care of formatting, mounting and using the instance store when in Raid0 (for kubelet, containers and ephemeral storage)
      # blockDeviceMappings = [{}] # If using EBS, we need more IOPS and throughput than the free defaults (300 - 125) as plugin tests are I/O bound

      role = module.cijenkinsio_agents_2_karpenter.node_iam_role_name

      subnetSelectorTerms = [{ id = module.vpc.private_subnets[3] }]
      securityGroupSelectorTerms = [
        {
          id = module.cijenkinsio_agents_2.node_security_group_id
        }
      ]
      amiSelectorTerms = [
        {
          # Few notes about AMI aliases (ref. karpenter and AWS EKS docs.)
          # - WindowsXXXX only has the "latest" version available
          # - Amazon Linux 2023 is our default OS choice for Linux containers nodes
          alias = startswith(each.value.os, "windows") ? "${replace(each.value.os, "-", "")}@latest" : "al2023@v${split("-", local.cijenkinsio_agents_2_ami_release_version)[1]}"
        }
      ]
    }
  }
}
