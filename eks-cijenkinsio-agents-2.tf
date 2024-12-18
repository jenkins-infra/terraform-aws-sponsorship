# Define a KMS main key to encrypt the EKS cluster
resource "aws_kms_key" "cijenkinsio-agents-2" {
  description         = "EKS Secret Encryption Key for the cluster cijenkinsio-agents-2"
  enable_key_rotation = true

  tags = merge(local.common_tags, {
    associated_service = "eks/cijenkinsio-agents-2"
  })
}

# EKS Cluster definition
module "cijenkinsio-agents-2" {
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
  # useful for autoscaler, EKS addons and any AWS APi usage
  enable_irsa = true

  # Allow the terraform CI IAM user to be co-owner of the cluster
  enable_cluster_creator_admin_permissions = true

  # avoid using config map to specify admin accesses (decrease attack surface)
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
    }
  }

  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.cijenkinsio-agents-2.arn
    resources        = ["secrets"]
  }

  ## We only want to private access to the Control Plane except from infra.ci agents and VPN CIDRs (running outside AWS)
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = [for admin_ip in local.ssh_admin_ips : "${admin_ip}/32"]
  # Nodes and Pods require access to the Control Plane - https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html#cluster-endpoint-private
  # without needing to allow their IPs
  cluster_endpoint_private_access = true

  create_cluster_primary_security_group_tags = false

  # Do not use interpolated values from `local` in either keys and values of provided tags (or `cluster_tags)
  # To avoid having and implicit dependency to a resource not available when parsing the module (infamous errror `Error: Invalid for_each argument`)
  # Ref. same error as having a `depends_on` in https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2337
  tags = merge(local.common_tags, {
    GithubRepo = "terraform-aws-sponsorship"
    GithubOrg  = "jenkins-infra"

    associated_service = "eks/cijenkinsio-agents-2"
  })

  # VPC is defined in vpc.tf
  vpc_id = module.vpc.vpc_id

  ## Manage EKS addons with module - https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon
  # See new versions with `aws eks describe-addon-versions --kubernetes-version <k8s-version> --addon-name <addon>`
  cluster_addons = {
    # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
    coredns = {
      addon_version = "v1.11.3-eksbuild.2"
    }
    # Kube-proxy on an Amazon EKS cluster has the same compatibility and skew policy as Kubernetes
    # See https://kubernetes.io/releases/version-skew-policy/#kube-proxy
    kube-proxy = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = "v1.29.10-eksbuild.3"
    }
    # https://github.com/aws/amazon-vpc-cni-k8s/releases
    vpc-cni = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = "v1.19.0-eksbuild.1"
    }
    eks-pod-identity-agent = {
      # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
      addon_version = "v1.3.4-eksbuild.1"
    }
    ## https://github.com/kubernetes-sigs/aws-ebs-csi-driver/blob/master/CHANGELOG.md
    # aws-ebs-csi-driver = {
    #   # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-addon-versions.html
    #   addon_version = "v1.37.0-eksbuild.1"
    #   # TODO specify service account
    #   # service_account_role_arn = module.cijenkinsio-agents-2_irsa_ebs.iam_role_arn
    # }
  }

  eks_managed_node_groups = {
    tiny_ondemand_linux = {
      # This worker pool is expected to host the "technical" services such as pod autoscaler, etc.
      name = "tiny-ondemand-linux"

      instance_types = ["t4g.large"] # 2vcpu 8Gio
      capacity_type  = "ON_DEMAND"
      # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
      ami_type     = "AL2023_ARM_64_STANDARD"
      min_size     = 1
      max_size     = 3
      desired_size = 1

      subnet_ids = slice(module.vpc.private_subnets, 1, 2) # Only 1 subnet in 1 AZ
    },
  }

  # Allow egress from nodes (and pods...)
  node_security_group_additional_rules = {
    egress_jenkins_jnlp = {
      description      = "Allow egress to Jenkins TCP"
      protocol         = "TCP"
      from_port        = 50000
      to_port          = 50000
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    },
    egress_http = {
      description      = "Allow egress to plain HTTP"
      protocol         = "TCP"
      from_port        = 80
      to_port          = 80
      type             = "egress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    },
  }
}

# Configure the jenkins-infra/kubernetes-management admin service account
data "aws_eks_cluster_auth" "cijenkinsio-agents-2" {
  name = module.cijenkinsio-agents-2.cluster_name
}

provider "kubernetes" {
  alias                  = "cijenkinsio-agents-2"
  host                   = module.cijenkinsio-agents-2.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cijenkinsio-agents-2.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cijenkinsio-agents-2.token
}

module "cijenkinsio-agents-2_admin_sa" {
  providers = {
    kubernetes = kubernetes.cijenkinsio-agents-2
  }
  source                     = "./.shared-tools/terraform/modules/kubernetes-admin-sa"
  cluster_name               = module.cijenkinsio-agents-2.cluster_name
  cluster_hostname           = module.cijenkinsio-agents-2.cluster_endpoint
  cluster_ca_certificate_b64 = module.cijenkinsio-agents-2.cluster_certificate_authority_data
}

output "kubeconfig_cijenkinsio-agents-2" {
  sensitive = true
  value     = module.cijenkinsio-agents-2_admin_sa.kubeconfig
}
