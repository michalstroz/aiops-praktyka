# Odpowiednik k8s/netpol-postgres.yaml w Terraform.
# Uwierzytelnienie jak w kubectl: kubeconfig uruchamia `aws eks get-token` z AWS_PROFILE=aiops.
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

locals {
  postgres_selector = {
    "app.kubernetes.io/name"     = "postgres"
    "app.kubernetes.io/instance" = "kantyna"
  }
  orders_api_selector = {
    "app.kubernetes.io/name"     = "orders-api"
    "app.kubernetes.io/instance" = "kantyna"
  }
}

# Do Postgresa Kantyny wpuszcza tylko pody orders-api z tego samego namespace, TCP 5432.
resource "kubernetes_network_policy_v1" "postgres_allow_orders_api" {
  metadata {
    name      = "kantyna-postgres-allow-orders-api"
    namespace = var.namespace
    labels = merge(local.postgres_selector, {
      "app.kubernetes.io/component" = "postgres"
      "app.kubernetes.io/part-of"   = "kantyna"
    })
  }

  spec {
    pod_selector {
      match_labels = local.postgres_selector
    }

    policy_types = ["Ingress"]

    ingress {
      # pod_selector bez namespace_selector = tylko pody z namespace tej polityki
      from {
        pod_selector {
          match_labels = local.orders_api_selector
        }
      }

      ports {
        protocol = "TCP"
        port     = "5432"
      }
    }
  }
}
