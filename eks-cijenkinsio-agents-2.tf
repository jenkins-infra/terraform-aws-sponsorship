################################################################################
# EKS Cluster ci.jenkins.io agents-2 definition
################################################################################
module "cijenkinsio_agents_2" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.1"

  cluster_name = "cijenkinsio-agents-2"
  # Kubernetes version in format '<MINOR>.<MINOR>', as per https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
  cluster_version = "1.31"
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
      # Ensure vpc-cni changes are applied before any EC2 instances are created
      before_compute = true
      configuration_values = jsonencode({
        # Allow Windows NODE, but requires access entry for node IAM profile to be of kind 'EC2_WINDOWS' to get the proper IAM permissions (otherwise DNS does not resolve on Windows pods)
        enableWindowsIpam = "true"
      })
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
      service_account_role_arn = aws_iam_role.s3_ci_jenkins_io_maven_cache.arn
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
  version = "5.58.0"

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
