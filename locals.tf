locals {
  cluster_name   = "aws-sponso"
  aws_account_id = "326712726440"
  region         = "us-east-2"
  our_az         = format("${local.region}%s", "b")
  outbound_ips = { # source : https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
    trusted.ci.jenkins.io              = ["104.209.128.236", "172.177.128.34", "172.210.175.108", "172.210.170.228"] # permanent agent of update_center2
    privatek8s.jenkins.io              = ["20.65.63.127"]                                                            # VPN VM
    infracijenkinsioagents1.jenkins.io = ["20.122.14.108", "20.186.70.154"]                                          # Terraform management and Docker-packaging build
    private.vpn.jenkins.io             = ["172.176.126.194"]                                                         # connections routed through the VPN
  }
  common_tags = {
    "scope"      = "terraform-managed"
    "repository" = "jenkins-infra/terraform-aws-sponsorship"
  }
}
