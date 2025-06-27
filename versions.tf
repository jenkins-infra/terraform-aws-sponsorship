
terraform {
  required_version = ">= 1.12, <1.13"
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # # Until https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3386 is fixed (note: also for VPC module)
      version = "~> 5.0"
    }
    local = {
      source = "hashicorp/local"
    }
    # Required by the EKS module
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    # Required by the EKS module
    null = {
      source = "hashicorp/null"
    }
    # Required by the EKS module
    time = {
      source = "hashicorp/time"
    }
    # Required by the EKS module
    tls = {
      source = "hashicorp/tls"
    }
    # Required by the EKS module
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    # Required by the EKS module
    helm = {
      source = "hashicorp/helm"
      # https://github.com/terraform-aws-modules/terraform-aws-eks/issues/3383#issuecomment-2987712505
      version = "~> 2"
    }
    # Required by the secrets-manager module
    random = {
      source = "hashicorp/random"
    }
  }
}
