
terraform {
  required_version = ">= 1.11, <1.12"
  required_providers {
    aws = {
      source = "hashicorp/aws"
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
    }
    # Required by the secrets-manager module
    random = {
      source = "hashicorp/random"
    }
  }
}
