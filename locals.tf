locals {
  aws_account_id = "326712726440"
  region         = "us-east-2"

  common_tags = {
    "scope"      = "terraform-managed"
    "repository" = "jenkins-infra/terraform-aws-sponsorship"
  }
}
