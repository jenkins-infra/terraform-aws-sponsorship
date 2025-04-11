
# As per https://github.com/hashicorp/terraform-provider-aws/issues/2420
# and https://github.com/aws/aws-cli/issues/3875
# we cannot use the AWS_PROFILE env. var. So we use this TF variable
# (or the --profile flag in AWS CLI)
variable "aws_profile" {
  type        = string
  default     = "terraform-developer"
  description = "AWS CLI profile to use with terraform"
}

variable "terratest" {
  type        = bool
  description = "value"
  default     = false
}
