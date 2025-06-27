# ####################################################################################
# # ci.jenkins.io resources
# ####################################################################################

# ### Network resources
# resource "aws_eip" "ci_jenkins_io" {
#   domain = "vpc"
# }

# resource "aws_eip_association" "ci_jenkins_io" {
#   instance_id   = aws_instance.ci_jenkins_io.id
#   allocation_id = aws_eip.ci_jenkins_io.id
# }

# ### IAM Resources (to allow instance profile instance of credentials for the controller VM to use ec2 plugin)
# data "aws_iam_policy_document" "assume_role_ec2" {
#   statement {
#     actions = ["sts:AssumeRole"]

#     principals {
#       type        = "Service"
#       identifiers = ["ec2.amazonaws.com"]
#     }
#   }
# }
# resource "aws_iam_role" "ci_jenkins_io" {
#   name = "ci-jenkins-io"

#   assume_role_policy = data.aws_iam_policy_document.assume_role_ec2.json

#   tags = local.common_tags
# }
# resource "aws_iam_instance_profile" "ci_jenkins_io" {
#   name = "ci-jenkins-io"
#   role = aws_iam_role.ci_jenkins_io.name
# }
# resource "aws_iam_role_policy" "ci_jenkins_io_ec2_agents" {
#   name = "ci-jenkins-io-ec2-agents"
#   role = aws_iam_role.ci_jenkins_io.id

#   policy = data.aws_iam_policy_document.jenkins_ec2_agents.json
# }
# # Permissions required by ECR (to allow using pull through after "aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account ID>.dkr.ecr.<region>.amazonaws.com")
# resource "aws_iam_role_policy_attachment" "ci_jenkins_io_read_ecr" {
#   # AmazonEC2ContainerRegistryReadOnly
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
#   role       = aws_iam_role.ci_jenkins_io.id
# }
# resource "aws_iam_role_policy_attachment" "ci_jenkins_io_ecrpullthroughcache" {
#   # ECRPullThroughCache
#   policy_arn = aws_iam_policy.ecrpullthroughcache.arn
#   role       = aws_iam_role.ci_jenkins_io.id
# }
# # Permissions required by Jenkins EC2 plugin in https://plugins.jenkins.io/ec2/#plugin-content-iam-setup
# data "aws_iam_policy_document" "jenkins_ec2_agents" {
#   # Minimum set of permissions
#   statement {
#     sid    = "jenkinsEC2"
#     effect = "Allow"

#     actions = [
#       "ec2:DescribeSpotInstanceRequests",
#       "ec2:CancelSpotInstanceRequests",
#       "ec2:GetConsoleOutput",
#       "ec2:RequestSpotInstances",
#       "ec2:RunInstances",
#       "ec2:StartInstances",
#       "ec2:StopInstances",
#       "ec2:TerminateInstances",
#       "ec2:CreateTags",
#       "ec2:DeleteTags",
#       "ec2:DescribeInstances",
#       "ec2:DescribeInstanceTypes",
#       "ec2:DescribeKeyPairs",
#       "ec2:DescribeRegions",
#       "ec2:DescribeImages",
#       "ec2:DescribeAvailabilityZones",
#       "ec2:DescribeSecurityGroups",
#       "ec2:DescribeSubnets",
#       "iam:ListInstanceProfilesForRole",
#       "iam:PassRole",
#       "ec2:GetPasswordData",
#     ]
#     ## We allow all resources names
#     # tfsec:ignore:AWS099
#     resources = ["*"]
#   }
# }

# ### Compute Resources
# resource "aws_key_pair" "ci_jenkins_io" {
#   key_name = "ci-jenkins-io"
#   # Private key 'id_jenkins-infra-team' encrypted in our SOPS vault
#   public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKvZ23dkvhjSU0Gxl5+mKcBOwmR7gqJDYeA1/Xzl3otV4CtC5te5Vx7YnNEFDXD6BsNkFaliXa34yE37WMdWl+exIURBMhBLmOPxEP/cWA5ZbXP//78ejZsxawBpBJy27uQhdcR0zVoMJc8Q9ShYl5YT/Tq1UcPq2wTNFvnrBJL1FrpGT+6l46BTHI+Wpso8BK64LsfX3hKnJEGuHSM0GAcYQSpXAeGS9zObKyZpk3of/Qw/2sVilIOAgNODbwqyWgEBTjMUln71Mjlt1hsEkv3K/VdvpFNF8VNq5k94VX6Rvg5FQBRL5IrlkuNwGWcBbl8Ydqk4wrD3b/PrtuLBEUsqbNhLnlEvFcjak+u2kzCov73csN/oylR0Tkr2y9x2HfZgDJVtvKjkkc4QERo7AqlTuy1whGfDYsioeabVLjZ9ahPjakv9qwcBrEEF+pAya7Q3AgNFVSdPgLDEwEO8GUHaxAjtyXXv9+yPdoDGmG3Pfn3KqM6UZjHCxne3Dr5ZE="
# }

# resource "aws_instance" "ci_jenkins_io" {
#   ami           = "ami-0700ac71a4832f3b3" # Ubuntu 22.04 - arm64 - 2024-11-15 (no need to update it unless if recreating the VM)
#   instance_type = "m7g.2xlarge"           # 8 vcpus Graviton 32Go https://aws.amazon.com/fr/ec2/instance-types/

#   iam_instance_profile = aws_iam_instance_profile.ci_jenkins_io.name

#   subnet_id                   = module.vpc.public_subnets[0]
#   associate_public_ip_address = true
#   vpc_security_group_ids = [
#     aws_security_group.restricted_in_ssh.id,
#     aws_security_group.unrestricted_in_http.id,
#     aws_security_group.unrestricted_out_http.id,
#     aws_security_group.allow_out_puppet_jenkins_io.id,
#     aws_security_group.ci_jenkins_io_controller.id,
#   ]

#   key_name = aws_key_pair.ci_jenkins_io.key_name

#   disable_api_termination = true # Protect ourselves from accidental deletion

#   user_data = templatefile("${path.root}/.shared-tools/terraform/cloudinit.tftpl", { hostname = local.ci_jenkins_io["controller_vm_fqdn"], admin_username = "ubuntu" })

#   root_block_device {
#     delete_on_termination = false # Even if we terminate the machine
#     encrypted             = true
#     volume_type           = "gp3"
#     volume_size           = 300
#     throughput            = 200  # Mb/s. Default (and free) for gp3 is 125.
#     iops                  = 6000 # Default (and free) for gp3 is 3000.

#     tags = local.common_tags

#   }

#   ebs_optimized = true

#   metadata_options {
#     # EC2 recommends setting IMDSv2 to required - https://aws.amazon.com/blogs/security/get-the-full-benefits-of-imdsv2-and-disable-imdsv1-across-your-aws-infrastructure/
#     http_tokens = "required"
#     # Needed to obtain IMDSv2 token from inside a docker container with a NAT network + AWS SDK proxy
#     http_put_response_hop_limit = 3
#   }

#   tags = merge(
#     local.common_tags,
#     { "Name" = "ci-jenkins-io" }
#   )
# }

# ## SSH Key used to access EC2 Agents (private key stored encrypted in SOPS)
# resource "aws_key_pair" "deployer" {
#   key_name   = "deployer-key"
#   public_key = trimspace(element(split("#", compact(split("\n", file("./ec2_agents_authorized_keys")))[0]), 0))
#   tags       = local.common_tags
# }

# ### DNS Zone delegated from Azure DNS (jenkins-infra/azure-net)
# # `updatecli` maintains sync between the 2 repositories using the infra reports (see outputs.tf)
# resource "aws_route53_zone" "aws_ci_jenkins_io" {
#   name = local.ci_jenkins_io["controller_vm_fqdn"]

#   tags = local.common_tags
# }

# resource "aws_route53_record" "a_aws_ci_jenkins_io" {
#   zone_id = aws_route53_zone.aws_ci_jenkins_io.zone_id
#   name    = local.ci_jenkins_io["controller_vm_fqdn"]
#   type    = "A"
#   ttl     = 60
#   records = [aws_eip.ci_jenkins_io.public_ip]
# }

# resource "aws_route53_record" "aaaa_aws_ci_jenkins_io" {
#   zone_id = aws_route53_zone.aws_ci_jenkins_io.zone_id
#   name    = local.ci_jenkins_io["controller_vm_fqdn"]
#   type    = "AAAA"
#   ttl     = 60
#   records = aws_instance.ci_jenkins_io.ipv6_addresses
# }

# resource "aws_route53_record" "a_assets_aws_ci_jenkins_io" {
#   zone_id = aws_route53_zone.aws_ci_jenkins_io.zone_id
#   name    = "assets.${local.ci_jenkins_io["controller_vm_fqdn"]}"
#   type    = "A"
#   ttl     = 60
#   records = [aws_eip.ci_jenkins_io.public_ip]
# }

# resource "aws_route53_record" "aaaa_assets_aws_ci_jenkins_io" {
#   zone_id = aws_route53_zone.aws_ci_jenkins_io.zone_id
#   name    = "assets.${local.ci_jenkins_io["controller_vm_fqdn"]}"
#   type    = "AAAA"
#   ttl     = 60
#   records = aws_instance.ci_jenkins_io.ipv6_addresses
# }

# ##########################################################################################################################################################
# ## Section: S3 Bucket used for storing Artifact and stashes
# ## This bucket does not need logging, versioning nor encryption as all objects are public
# #trivy:ignore:AVD-AWS-0089 trivy:ignore:aws-s3-enable-versioning trivy:ignore:aws-s3-enable-bucket-logging trivy:ignore:aws-s3-encryption-customer-key trivy:ignore:aws-s3-enable-bucket-encryption
# resource "aws_s3_bucket" "ci_jenkins_io_artifacts" {
#   bucket = "aws-ci-jenkins-io-artifacts"

#   force_destroy = true

#   tags = merge(local.common_tags, { jenkins = "ci.jenkins.io" })
# }

# resource "aws_s3_bucket_public_access_block" "ci_jenkins_io_artifacts" {
#   bucket                  = aws_s3_bucket.ci_jenkins_io_artifacts.id
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }

# resource "aws_s3_bucket_lifecycle_configuration" "ci_jenkins_io_artifacts" {
#   bucket = aws_s3_bucket.ci_jenkins_io_artifacts.id
#   rule {
#     status = "Enabled"
#     id     = "expire_all_files"
#     expiration {
#       days = 30
#     }
#     filter {
#       prefix = ""
#     }
#   }
# }

# resource "aws_iam_role_policy" "ci_jenkins_io_artifacts" {
#   name = "ci-jenkins-io-artifacts"
#   role = aws_iam_role.ci_jenkins_io.id

#   policy = data.aws_iam_policy_document.ci_jenkins_io_artifacts_iam.json
# }

# data "aws_iam_policy_document" "ci_jenkins_io_artifacts_iam" {
#   statement {
#     actions   = ["s3:ListBucket"]
#     resources = [aws_s3_bucket.ci_jenkins_io_artifacts.arn]
#     effect    = "Allow"
#   }
#   statement {
#     actions = [
#       "s3:GetBucketLocation",
#       "s3:GetObject",
#       "s3:DeleteObject",
#       "s3:ListObjects",

#     ]
#     resources = [aws_s3_bucket.ci_jenkins_io_artifacts.arn]
#     effect    = "Allow"
#   }
# }

# resource "aws_s3_bucket_policy" "ci_jenkins_io_artifacts" {
#   bucket = aws_s3_bucket.ci_jenkins_io_artifacts.id
#   policy = data.aws_iam_policy_document.ci_jenkins_io_artifacts_objects.json
# }

# data "aws_iam_policy_document" "ci_jenkins_io_artifacts_objects" {
#   statement {
#     principals {
#       type = "AWS"
#       identifiers = [
#         resource.aws_iam_role.ci_jenkins_io.arn,
#       ]
#     }

#     actions = [
#       "s3:PutObject",
#       "s3:GetObject",
#     ]

#     resources = [
#       aws_s3_bucket.ci_jenkins_io_artifacts.arn,
#       "${aws_s3_bucket.ci_jenkins_io_artifacts.arn}/*",
#     ]
#   }
# }
# # End of S3 Bucket Section
# ##########################################################################################################################################################
