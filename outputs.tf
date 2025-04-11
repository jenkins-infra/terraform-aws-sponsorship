resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "${local.ci_jenkins_io["controller_vm_fqdn"]}" = {
      "outbound_ips" = {
        "agents" = module.vpc.nat_public_ips,
      },
      "ec2-agents" = {
        "subnet_ids" = [module.vpc.private_subnets[0]],
      },
    }
  })
  filename = "${path.module}/jenkins-infra-data-reports/aws-sponsorship.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
