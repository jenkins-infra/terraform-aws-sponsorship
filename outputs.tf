resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "${local.ci_jenkins_io["controller_vm_fqdn"]}" = {
      "name_servers" = aws_route53_zone.aws_ci_jenkins_io.name_servers,
      "service_ips" = {
        "ipv4" = aws_eip.ci_jenkins_io.public_ip,
        "ipv6" = aws_instance.ci_jenkins_io.ipv6_addresses[0],
      },
      "outbound_ips" = {
        "agents" = module.vpc.nat_public_ips,
        "controller" = concat(
          aws_instance.ci_jenkins_io.ipv6_addresses, # Public IPv6(s) (usually list of one element)
          [aws_eip.ci_jenkins_io.public_ip],         # Public IPv4 of the controller
        ),
      },
      "ec2-agents" = {
        "subnet_ids" = [module.vpc.private_subnets[0]],
        "security_group_names" = [
          aws_security_group.ephemeral_vm_agents.name,
          aws_security_group.unrestricted_out_http.name,
        ]
      },
      "cijenkinsio-agents-2" = {
        "cluster_endpoint"  = module.cijenkinsio_agents_2.cluster_endpoint,
        "kubernetes_groups" = local.cijenkinsio_agents_2.kubernetes_groups,
        "node_groups" = merge(
          {
            "applications" = {
              "labels"      = module.cijenkinsio_agents_2.eks_managed_node_groups["applications"].node_group_labels
              "tolerations" = local.cijenkinsio_agents_2["system_node_pool"]["tolerations"],
            }
          },
          { for knp in local.cijenkinsio_agents_2.karpenter_node_pools :
            knp.name => {
              "labels" = knp.nodeLabels,
              "tolerations" = [for taint in knp.taints : {
                "effect" : taint.effect,
                "key" : taint.key,
                "operator" : "Equal",
                "value" : "true"
              }]
            }
          },
        )
        artifact_caching_proxy = {
          subnet_ids = local.cijenkinsio_agents_2.artifact_caching_proxy.subnet_ids,
          ips        = local.cijenkinsio_agents_2.artifact_caching_proxy.ips,
        },
        docker_registry_mirror = {
          subnet_ids = local.cijenkinsio_agents_2.docker_registry_mirror.subnet_ids,
          ips        = local.cijenkinsio_agents_2.docker_registry_mirror.ips,
        },
        "subnet_ids" = [module.vpc.private_subnets[1], module.vpc.private_subnets[2], module.vpc.private_subnets[3]],
      },
      artifacts_manager = {
        s3_bucket_name = aws_s3_bucket.ci_jenkins_io_artifacts.bucket
      },
    },
  })
  filename = "${path.module}/jenkins-infra-data-reports/aws-sponsorship.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
