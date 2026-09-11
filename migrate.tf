## Kubernetes 2.X -> 3.X - Migration file
# Inspired by https://github.com/hashicorp/terraform-provider-kubernetes/issues/2812#issuecomment-3733845983

removed {
  from = module.cijenkinsio_agents_2_admin_sa.kubernetes_cluster_role_binding.infraciadmin_clusteradmin
  lifecycle {
    destroy = false
  }
}
import {
  id = "infraciadmin_clusteradmin"
  to = module.cijenkinsio_agents_2_admin_sa.kubernetes_cluster_role_binding_v1.infraciadmin_clusteradmin
}
