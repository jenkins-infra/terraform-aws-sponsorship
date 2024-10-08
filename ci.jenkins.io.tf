resource "aws_instance" "aws-ci.jenkins.io" {
  ami           = local.aws_ci_jenkins_io_image_ami_id # we lock the image x86/64
  instance_type = "m8g.2xlarge" # 8vcpu 32Go https://aws.amazon.com/fr/ec2/instance-types/

  tags = local.common_tags
}

