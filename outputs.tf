# resource "local_file" "jenkins_infra_data_report" {
#   content = jsonencode({
#     "${local.ci_jenkins_io["controller_vm_fqdn"]}" = {
#       "name_servers" = aws_route53_zone.aws_ci_jenkins_io.name_servers,
#       "service_ips" = {
#         "ipv4" = aws_eip.ci_jenkins_io.public_ip,
#         "ipv6" = aws_instance.ci_jenkins_io.ipv6_addresses[0],
#       },
#       "outbound_ips" = {
#         "agents" = module.vpc.nat_public_ips,
#         "controller" = concat(
#           aws_instance.ci_jenkins_io.ipv6_addresses, # Public IPv6(s) (usually list of one element)
#           [aws_eip.ci_jenkins_io.public_ip],         # Public IPv4 of the controller
#         ),
#       },
#       "ec2-agents" = {
#         "subnet_ids" = [module.vpc.private_subnets[0]],
#         "security_group_names" = [
#           aws_security_group.ephemeral_vm_agents.name,
#           aws_security_group.unrestricted_out_http.name,
#         ]
#       },
#       artifacts_manager = {
#         s3_bucket_name = aws_s3_bucket.ci_jenkins_io_artifacts.bucket
#       },
#     },

#   })
#   filename = "${path.module}/jenkins-infra-data-reports/aws-sponsorship.json"
# }
# output "jenkins_infra_data_report" {
#   value = local_file.jenkins_infra_data_report.content
# }
