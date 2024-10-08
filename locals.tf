locals {
  aws_account_id = "326712726440"
  aws_ci_jenkins_io_image_ami_id = "ami-089146c5626baa6bf" # Verified provider Ubuntu Server 22.04 LTS (HVM), SSD Volume Type ami-089146c5626baa6bf (64-bit (x86)) / ami-057b0e5f4e7564dab (64-bit (Arm))
  common_tags = {
    "scope"      = "terraform-managed"
    "repository" = "jenkins-infra/terraform-aws-sponsorship"
  }
}
