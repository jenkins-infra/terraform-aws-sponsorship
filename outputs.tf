resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
  })
  filename = "${path.module}/jenkins-infra-data-reports/aws-sponsorship.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
