data "aws_eks_cluster_auth" "qa_cluster_auth" {
  name = aws_eks_cluster.qa_cluster.name
}

provider "kubernetes" {
  host = aws_eks_cluster.qa_cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.qa_cluster.certificate_authority[0].data)
  token = data.aws_eks_cluster_auth.qa_cluster_auth.token
  load_config_file = false
  # when you wish not to load the local config file
}

resource "kubernetes_certificate_signing_request" "cert_sign" {
  metadata {
    name = "certificate-signing"
  }
  auto_approve = true
  spec {
    usages = [
      "client auth",
      "server auth"]
    request = <<EOT
-----BEGIN CERTIFICATE REQUEST-----
MIHSMIGBAgEAMCoxGDAWBgNVBAoTD2V4YW1wbGUgY2x1c3RlcjEOMAwGA1UEAxMF
YWRtaW4wTjAQBgcqhkjOPQIBBgUrgQQAIQM6AASSG8S2+hQvfMq5ucngPCzK0m0C
ImigHcF787djpF2QDbz3oQ3QsM/I7ftdjB/HHlG2a5YpqjzT0KAAMAoGCCqGSM49
BAMCA0AAMD0CHQDErNLjX86BVfOsYh/A4zmjmGknZpc2u6/coTHqAhxcR41hEU1I
DpNPvh30e0Js8/DYn2YUfu/pQU19
-----END CERTIFICATE REQUEST-----
EOT
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node]
}

//-------------------------------Jenkins namespace--------------------------

resource "kubernetes_namespace" "jenkins_ns" {
  metadata {
    name = "jenkins"

    labels = {
      run = "jenkins"
    }
  }
}

//--------------------------------Jenkins Deployment------------------------

resource "kubernetes_deployment" "jenkins" {
  metadata {
    name = "jenkins-deploy"
    namespace = kubernetes_namespace.jenkins_ns.metadata[0].name
    labels = {
      run = "jenkins"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        run = "jenkins"
      }
    }
    template {
      metadata {
        namespace = kubernetes_namespace.jenkins_ns.metadata[0].name
        labels = {
          run = "jenkins"
        }
      }
      spec {
        container {
          name = "jenkins"
          image = "jenkins/jenkins:lts"
          image_pull_policy = "Always"
          port {
            container_port = 8080
            protocol = "TCP"
          }
          volume_mount {
            mount_path = "/var/jenkins_home"
            name = "jenkins-home"
          }
        }
        volume {
          name = "jenkins-home"
          empty_dir {}
        }
      }
    }
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node]
}

resource "kubernetes_pod" "jenkins_agent" {
  metadata {
    name = "jenkins-agent"
    namespace = kubernetes_namespace.jenkins_ns.metadata[0].name
    labels = {
      run = "jenkins-agent"
    }
  }
  spec {
    container {
      name = "jenkins-slave"
      image = "joao29a/jnlp-slave-alpine-docker:latest"
//      image = "jenkins/slave"
      port {
        container_port = 50000
      }
      resources {
        requests {
          cpu = "200m"
          memory = "256Mi"
        }
        limits {
          cpu = "500m"
          memory = "512Mi"
        }
      }
      volume_mount {
        mount_path = "/var/run/docker.sock"
        name = "docker-sock"
      }
    }
    volume {
      name = "docker-sock"
      host_path {
        path = "/var/run/docker.sock"
        type = "Socket"
      }
    }
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node]
}

//-------------------------------Jenkins service----------------------------

resource "kubernetes_service" "jenkins_svc" {
  metadata {
    name = "jenkins-service"
    namespace = kubernetes_namespace.jenkins_ns.metadata[0].name
    labels = {
      run = "jenkins"
    }
  }
  spec {
    port {
      port = 8080
      protocol = "TCP"
      node_port = 32300
    }
    selector = {
      run = "jenkins"
    }
    type = "NodePort"
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node]
}

resource "kubernetes_service" "jenkins_agent_svc" {
  metadata {
    name = "jenkins-agent"
    namespace = kubernetes_namespace.jenkins_ns.metadata[0].name
    labels = {
      run = "jenkins-agent"
    }
  }
  spec {
    port {
      port = 50000
      protocol = "TCP"
    }
    selector = {
      run = "jenkins-agent"
    }
    type = "ClusterIP"
  }
  depends_on = [
    aws_eks_cluster.qa_cluster,
    aws_eks_node_group.qa_cluster_node]
}

//----------------------------Private local registry------------------------------

resource "kubernetes_stateful_set" "local_repo" {
  metadata {
    name = "local-registry"
    labels = {
      k8s-app = "local-registry"
      "kubernetes.io/cluster-service" = "true"
    }
  }
  spec {
    service_name = "local-registry"
    pod_management_policy = "Parallel"
    replicas = 1
    revision_history_limit = 5
    selector {
      match_labels = {
        k8s-app = "local-registry"
      }
    }
    template {
      metadata {
        labels = {
          k8s-app = "local-registry"
        }
      }
      spec {
        container {
          name = "local-registry"
          image = "registry:2"
          image_pull_policy = "IfNotPresent"

          /*          volume_mount {
                      mount_path = "/var/lib/registry"
                      name = "local-repo-volume"
                    }*/
          port {
            container_port = 5000
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "local_repo_svc" {
  metadata {
    name = "local-registry-svc"
  }
  spec {
    selector = {
      k8s-app = "local-registry"
    }
    port {
      port = 5000
      target_port = 5000
    }
    type = "ClusterIP"
  }
}

//---------------------------Prometheus solution---------------------------

resource "kubernetes_stateful_set" "prometheus" {
  metadata {
    labels = {
      k8s-app = "prometheus"
      "kubernetes.io/cluster-service" = "true"
      "addonmanager.kubernetes.io/mode" = "Reconcile"
      version = "v2.2.1"
    }

    name = "prometheus"
  }

  spec {
    pod_management_policy = "Parallel"
    replicas = 1
    revision_history_limit = 5

    selector {
      match_labels = {
        k8s-app = "prometheus"
      }
    }

    service_name = "prometheus"

    template {
      metadata {
        labels = {
          k8s-app = "prometheus"
        }

        annotations = {}
      }

      spec {
        service_account_name = "prometheus"

        init_container {
          name = "init-chown-data"
          image = "busybox:latest"
          image_pull_policy = "IfNotPresent"
          command = [
            "chown",
            "-R",
            "65534:65534",
            "/data"]

          volume_mount {
            name = "prometheus-data"
            mount_path = "/data"
            sub_path = ""
          }
        }

        container {
          name = "prometheus-server-configmap-reload"
          image = "jimmidyson/configmap-reload:v0.1"
          image_pull_policy = "IfNotPresent"

          args = [
            "--volume-dir=/etc/config",
            "--webhook-url=http://localhost:9090/-/reload",
          ]

          volume_mount {
            name = "config-volume"
            mount_path = "/etc/config"
            read_only = true
          }

          resources {
            limits {
              cpu = "10m"
              memory = "10Mi"
            }

            requests {
              cpu = "10m"
              memory = "10Mi"
            }
          }
        }

        container {
          name = "prometheus-server"
          image = "prom/prometheus:v2.2.1"
          image_pull_policy = "IfNotPresent"

          args = [
            "--config.file=/etc/config/prometheus.yml",
            "--storage.tsdb.path=/data",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
            "--web.enable-lifecycle",
          ]

          port {
            container_port = 9090
          }

          resources {
            limits {
              cpu = "200m"
              memory = "1000Mi"
            }

            requests {
              cpu = "200m"
              memory = "1000Mi"
            }
          }

          volume_mount {
            name = "config-volume"
            mount_path = "/etc/config"
          }

          volume_mount {
            name = "prometheus-data"
            mount_path = "/data"
            sub_path = ""
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9090
            }

            initial_delay_seconds = 30
            timeout_seconds = 30
          }

          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = 9090
              scheme = "HTTPS"
            }

            initial_delay_seconds = 30
            timeout_seconds = 30
          }
        }

        termination_grace_period_seconds = 300

        volume {
          name = "config-volume"

          config_map {
            name = "prometheus-config"
          }
        }
      }
    }

    update_strategy {
      type = "RollingUpdate"

      rolling_update {
        partition = 1
      }
    }

    volume_claim_template {
      metadata {
        name = "prometheus-data"
      }

      spec {
        access_modes = [
          "ReadWriteOnce"]
        storage_class_name = "standard"

        resources {
          requests = {
            storage = "16Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "prometheus_svc" {
  metadata {
    name = "prometheus-svc"
  }
  spec {
    selector = {
      k8s-app = kubernetes_stateful_set.prometheus.metadata[0].labels.k8s-app
    }
    port {
      port = 9090
      node_port = 32090
    }
    type = "NodePort"
  }
}
