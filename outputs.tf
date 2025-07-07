resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "${local.ci_jenkins_io["controller_vm_fqdn"]}" = {
      "region"         = local.region,
      "aws_account_id" = local.aws_account_id,
      "name_servers"   = aws_route53_zone.aws_ci_jenkins_io.name_servers,
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
      "agents_azure_vms" = {
        "subnet_ids" = [module.vpc.private_subnets[0]],
        "security_group_names" = [
          aws_security_group.ephemeral_vm_agents.name,
          aws_security_group.unrestricted_out_http.name,
        ]
      },
      "agents_kubernetes_clusters" = {
        "cijenkinsio-agents-2" = {
          "cluster_endpoint"   = module.cijenkinsio_agents_2.cluster_endpoint,
          "kubernetes_version" = module.cijenkinsio_agents_2.cluster_version,
          "kubernetes_groups"  = local.cijenkinsio_agents_2.kubernetes_groups,
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
          ),
          "agents_namespaces" = {
            for agent_ns, agent_setup in local.cijenkinsio_agents_2.agent_namespaces : agent_ns => {
              "pods_quota"      = agent_setup["pods_quota"],
              "maven_cache_pvc" = kubernetes_persistent_volume_claim.ci_jenkins_io_maven_cache_readonly[agent_ns].metadata[0].name,
            }
          },
          "services" = {
            "artifact-caching-proxy" = {
              "subnet_ids"    = local.cijenkinsio_agents_2.artifact_caching_proxy.subnet_ids,
              "ips"           = local.cijenkinsio_agents_2.artifact_caching_proxy.ips,
              "storage_class" = kubernetes_storage_class.cijenkinsio_agents_2_ebs_csi_premium_retain[[for subnet_index, subnet_data in module.vpc.private_subnet_objects : subnet_data.availability_zone if local.cijenkinsio_agents_2["system_node_pool"]["subnet_ids"][0] == subnet_data.id][0]].metadata[0].name,
            },
            "hub-mirror" = {
              "subnet_ids"    = local.cijenkinsio_agents_2.docker_registry_mirror.subnet_ids,
              "ips"           = local.cijenkinsio_agents_2.docker_registry_mirror.ips,
              "storage_class" = kubernetes_storage_class.cijenkinsio_agents_2_ebs_csi_premium_retain[[for subnet_index, subnet_data in module.vpc.private_subnet_objects : subnet_data.availability_zone if local.cijenkinsio_agents_2["system_node_pool"]["subnet_ids"][0] == subnet_data.id][0]].metadata[0].name,
            },
            "maven-cacher" = {
              "namespace" = "${kubernetes_namespace.maven_cache.metadata[0].name}",
              "pvc"       = kubernetes_persistent_volume_claim.ci_jenkins_io_maven_cache_write.metadata[0].name,
            },
          },
        },
      },
      "artifacts_manager" = {
        "s3_bucket_name" = aws_s3_bucket.ci_jenkins_io_artifacts.bucket
      },
      "ecr" = {
        "docker_hub_cache_prefix" = "${local.aws_account_id}.dkr.ecr.${local.region}.amazonaws.com/docker-hub/"
      }
    },
  })
  filename = "${path.module}/jenkins-infra-data-reports/aws-sponsorship.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
