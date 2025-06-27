provider "aws" {
  region = local.region
  # profile = var.aws_profile
  assume_role {
    role_arn = "arn:aws:iam::326712726440:role/infra-developer"
  }

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  alias = "cijenkinsio_agents_2"

  host                   = module.cijenkinsio_agents_2.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cijenkinsio_agents_2.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cijenkinsio_agents_2.token
}

provider "helm" {
  alias = "cijenkinsio_agents_2"

  kubernetes {
    host                   = module.cijenkinsio_agents_2.cluster_endpoint
    token                  = data.aws_eks_cluster_auth.cijenkinsio_agents_2.token
    cluster_ca_certificate = base64decode(module.cijenkinsio_agents_2.cluster_certificate_authority_data)
  }
}
