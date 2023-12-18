provider "google" {
  region = "us-east5"
}

terraform {
  backend "gcs" {
    bucket = "production-prod01-042575-terraform-state"
    prefix = "prod"
  }
}

### VARIABLES ###
variable "billing_account" {
  description = "The ID of the billing account to associate projects with"
  type        = string
  default     = "0114F3-2A6259-D37B61"
}

variable "org_id" {
  description = "The organization id for the associated resources"
  type        = string
  default     = "943971376535"
}

variable "allow_icmp" {
  description = "Network tag to apply on any resource that should receive ICMP traffic"
  default     = "allow-icmp"
}

variable "allow_rdp" {
  description = "Network tag to apply on any resource that should receive RDP traffic"
  default     = "allow-rdp"
}

variable "allow_ssh" {
  description = "Network tag to apply on any resource that should receive SSH traffic"
  default     = "allow-ssh"
}

### PROJECTS ###
resource "google_project" "prod_project" {
  name            = "Production"
  project_id      = "production-prod01-042575"
  org_id          = var.org_id
  billing_account = var.billing_account
}

### IAM ###
resource "google_service_account" "gcs_service_account" {
  account_id   = "gcs-service-account"
  display_name = "Cloud Storage default service account"
  project      = google_project.prod_project.project_id
}

#Not sure if the service account creation above and role assignment below can be executed in the same Terraform Apply. May need to create service account first.
resource "google_project_iam_member" "gcs_service_account" {
  project = google_project.prod_project.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:gcs-service-account@production-prod01-042575.iam.gserviceaccount.com"
}

resource "google_storage_hmac_key" "key" {
  service_account_email = google_service_account.gcs_service_account.email
  project               = google_project.prod_project.project_id
}

### NETWORKS ###
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_network
resource "google_compute_network" "vpc_prod" {
  name                    = "vpc-prod"
  project                 = google_project.prod_project.project_id
  auto_create_subnetworks = true
}

### FIREWALLS ###
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_firewall 
resource "google_compute_firewall" "firewall_prod_allow_internal" {
  name        = "prod-allow-internal"
  project     = google_project.prod_project.project_id
  network     = google_compute_network.vpc_prod.name
  description = "Allows all traffic between subnets on the ${google_compute_network.vpc_prod.name} VPC"

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  direction = "INGRESS"

  source_ranges = ["10.128.0.0/9"]

  priority = 1000

  disabled = false

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "firewall_prod_allow_icmp" {
  name        = "prod-${var.allow_icmp}"
  project     = google_project.prod_project.project_id
  network     = google_compute_network.vpc_prod.name
  description = "Allows ICMP traffic from anywhere"

  allow {
    protocol = "icmp"
  }

  direction = "INGRESS"

  source_ranges = ["0.0.0.0/0"]

  priority = 1001

  disabled = false

  target_tags = ["${var.allow_icmp}"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "firewall_prod_allow_ssh" {
  name        = "prod-${var.allow_ssh}"
  project     = google_project.prod_project.project_id
  network     = google_compute_network.vpc_prod.name
  description = "Allows SSH traffic from anywhere"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  direction = "INGRESS"

  source_ranges = ["0.0.0.0/0"]

  priority = 1002

  disabled = false

  target_tags = ["${var.allow_ssh}"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_firewall" "firewall_prod_allow_rdp" {
  name        = "prod-${var.allow_rdp}"
  project     = google_project.prod_project.project_id
  network     = google_compute_network.vpc_prod.name
  description = "Allows RDP traffic from anywhere"

  allow {
    protocol = "tcp"
    ports    = ["3389"]
  }

  direction = "INGRESS"

  source_ranges = ["0.0.0.0/0"]

  priority = 1003

  disabled = false

  target_tags = ["${var.allow_rdp}"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}

### STORAGE ###
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket 
resource "google_storage_bucket" "terraform-state" {
  name                        = "${google_project.prod_project.project_id}-terraform-state"
  location                    = "US"
  uniform_bucket_level_access = true
  storage_class               = "STANDARD"
}

resource "google_storage_bucket" "ds1618-hyperbackup" {
  name                        = "${google_project.prod_project.project_id}-ds1618-hperbackup"
  location                    = "US-EAST5"
  uniform_bucket_level_access = true
  storage_class               = "STANDARD"

  lifecycle_rule {
    condition {
      age = 7
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}