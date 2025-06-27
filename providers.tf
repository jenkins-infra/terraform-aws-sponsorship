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
