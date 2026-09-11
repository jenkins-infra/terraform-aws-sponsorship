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

removed {
  from = kubernetes_namespace.jenkins_agents
  lifecycle {
    destroy = false
  }
}
import {
  id = "jenkins-agents"
  to = kubernetes_namespace_v1.jenkins_agents["jenkins-agents"]
}
import {
  id = "jenkins-agents-nonspot"
  to = kubernetes_namespace_v1.jenkins_agents["jenkins-agents-nonspot"]
}
import {
  id = "jenkins-agents-bom"
  to = kubernetes_namespace_v1.jenkins_agents["jenkins-agents-bom"]
}

removed {
  from = kubernetes_namespace.maven_cache
  lifecycle {
    destroy = false
  }
}
import {
  id = "maven-cache"
  to = kubernetes_namespace_v1.maven_cache
}

removed {
  from = kubernetes_persistent_volume.ci_jenkins_io_maven_cache_readonly
  lifecycle {
    destroy = false
  }
}
import {
  id = "ci-jenkins-io-maven-cache-jenkins-agents"
  to = kubernetes_persistent_volume_v1.ci_jenkins_io_maven_cache_readonly["jenkins-agents"]
}
import {
  id = "ci-jenkins-io-maven-cache-jenkins-agents-nonspot"
  to = kubernetes_persistent_volume_v1.ci_jenkins_io_maven_cache_readonly["jenkins-agents-nonspot"]
}
import {
  id = "ci-jenkins-io-maven-cache-jenkins-agents-bom"
  to = kubernetes_persistent_volume_v1.ci_jenkins_io_maven_cache_readonly["jenkins-agents-bom"]
}


removed {
  from = kubernetes_persistent_volume_claim.ci_jenkins_io_maven_cache_readonly
  lifecycle {
    destroy = false
  }
}
import {
  id = "jenkins-agents/ci-jenkins-io-maven-cache"
  to = kubernetes_persistent_volume_claim_v1.ci_jenkins_io_maven_cache_readonly["jenkins-agents"]
}
import {
  id = "jenkins-agents-nonspot/ci-jenkins-io-maven-cache"
  to = kubernetes_persistent_volume_claim_v1.ci_jenkins_io_maven_cache_readonly["jenkins-agents-nonspot"]
}
import {
  id = "jenkins-agents-bom/ci-jenkins-io-maven-cache"
  to = kubernetes_persistent_volume_claim_v1.ci_jenkins_io_maven_cache_readonly["jenkins-agents-bom"]
}
