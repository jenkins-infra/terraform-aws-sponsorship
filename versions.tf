
terraform {
  required_version = ">= 1.12, <1.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source = "hashicorp/local"
    }
    # Required by the EKS module
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    # Required by the secrets-manager module
    random = {
      source = "hashicorp/random"
    }
  }
}
