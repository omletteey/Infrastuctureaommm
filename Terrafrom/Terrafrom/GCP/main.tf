# Provider configuration is managed in backend.tf

resource "google_compute_network" "main" {
  name                    = "public-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  count         = 3
  name          = "public-subnet-${count.index + 1}"
  ip_cidr_range = cidrsubnet("10.0.0.0/16", 8, count.index + 1)
  region        = "asia-southeast1"
  network       = google_compute_network.main.id

  depends_on = [google_compute_network.main]
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }


  source_ranges = ["0.0.0.0/0"]

  depends_on = [google_compute_network.main]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]

  depends_on = [google_compute_network.main]
}

resource "google_compute_instance_template" "default" {
  name           = "web-template"
  machine_type   = "e2-medium"
  region         = "asia-southeast1"

  disk {
    source_image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network    = google_compute_network.main.id
    subnetwork = google_compute_subnetwork.public[0].id
    access_config {}
  }

  metadata = {
    ssh-keys = "gcpuser:${file("adminterra.pub")}"
  }

  metadata_startup_script = <<-EOF
      #!/bin/bash
      echo "Provision started at $(date)" >> /var/log/provision.log
      apt-get update -y
      apt-get install nginx -y
      
      # Create a custom index page to verify load balancer is working
      echo "<h1>Hello from Azure VM Scale Set!</h1>" > /var/www/html/index.html
      echo "<p>Server: $(hostname)</p>" >> /var/www/html/index.html
      echo "<p>Timestamp: $(date)</p>" >> /var/www/html/index.html
      
      systemctl enable nginx
      systemctl start nginx
      
      # Install Docker
      curl -fsSL https://get.docker.com -o get-docker.sh
      sh get-docker.sh
      usermod -aG docker gcpuser
      apt-get install docker-compose-plugin -y
      
      echo "Provision finished at $(date)" >> /var/log/provision.log
  EOF

  depends_on = [google_compute_subnetwork.public]
}

resource "google_compute_instance_group_manager" "web-mig" {
  name               = "web-mig"
  base_instance_name = "web"
  zone               = "asia-southeast1-b"

  version {
    instance_template = google_compute_instance_template.default.id
  }

  target_size = 3

  named_port {
    name = "http"
    port = 80
  }

  depends_on = [google_compute_instance_template.default]
}

resource "google_compute_autoscaler" "web-autoscaler" {
  name   = "web-autoscaler"
  zone   = "asia-southeast1-b"
  target = google_compute_instance_group_manager.web-mig.id

  autoscaling_policy {
    max_replicas    = 5
    min_replicas    = 3
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }

  depends_on = [google_compute_instance_group_manager.web-mig]
}

resource "google_compute_health_check" "http" {
  name               = "http-health-check"
  check_interval_sec = 30
  timeout_sec        = 10
  healthy_threshold  = 2
  unhealthy_threshold = 2

  http_health_check {
    port = 80
  }
}

resource "google_compute_backend_service" "default" {
  name                  = "web-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.http.id]
  load_balancing_scheme = "EXTERNAL"

  backend {
    group = google_compute_instance_group_manager.web-mig.instance_group
  }

  depends_on = [
    google_compute_instance_group_manager.web-mig,
    google_compute_health_check.http
  ]
}

resource "google_compute_url_map" "default" {
  name            = "web-url-map"
  default_service = google_compute_backend_service.default.id

  depends_on = [google_compute_backend_service.default]
}

resource "google_compute_target_http_proxy" "default" {
  name   = "web-http-proxy"
  url_map = google_compute_url_map.default.id

  depends_on = [google_compute_url_map.default]
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "web-forwarding-rule"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_protocol = "TCP"

  depends_on = [google_compute_target_http_proxy.default]
}
