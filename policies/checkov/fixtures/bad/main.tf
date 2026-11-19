resource "google_storage_bucket" "site" {
  name     = "example-site"
  location = "EU"
}

resource "google_compute_firewall" "ssh_world" {
  name          = "allow-ssh-world"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_storage_bucket_iam_member" "public" {
  bucket = google_storage_bucket.site.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_binding" "authenticated" {
  bucket  = google_storage_bucket.site.name
  role    = "roles/storage.objectViewer"
  members = ["allAuthenticatedUsers"]
}

resource "google_service_account_key" "ci" {
  service_account_id = "projects/example/serviceAccounts/ci@example.iam.gserviceaccount.com"
}

resource "google_compute_firewall" "ssh_in_second_block" {
  name          = "ssh-in-second-block"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "all_tcp_ports_range" {
  name          = "all-tcp-ports-range"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }
}

resource "google_compute_firewall" "range_covering_ssh" {
  name          = "range-covering-ssh"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["20-25"]
  }
}

resource "google_compute_firewall" "tcp_without_ports" {
  name          = "tcp-without-ports"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
  }
}

resource "google_compute_firewall" "protocol_all" {
  name          = "protocol-all"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "all"
  }
}

resource "google_compute_firewall" "numeric_tcp_ssh" {
  name          = "numeric-tcp-ssh"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "6"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "udp_rdp_ipv6" {
  name          = "udp-rdp-ipv6"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["::/0"]

  allow {
    protocol = "17"
    ports    = ["3389"]
  }
}

# Authoritative policy on an existing bucket (no google_storage_bucket here).
data "google_iam_policy" "public_site" {
  binding {
    role    = "roles/storage.legacyBucketOwner"
    members = ["projectOwner:example-project"]
  }
  binding {
    role    = "roles/storage.objectViewer"
    members = ["allUsers"]
  }
}

resource "google_storage_bucket_iam_policy" "existing_public" {
  bucket      = "existing-public-site"
  policy_data = data.google_iam_policy.public_site.policy_data
}

resource "google_storage_bucket_iam_policy" "existing_public_literal" {
  bucket = "existing-public-assets"
  policy_data = jsonencode({
    bindings = [{
      role    = "roles/storage.objectViewer"
      members = ["allAuthenticatedUsers"]
    }]
  })
}

resource "google_storage_bucket_acl" "public_reader" {
  bucket      = "existing-public-site"
  role_entity = ["OWNER:project-owners-123456", "READER:allUsers"]
}

resource "google_storage_bucket_access_control" "public_authenticated" {
  bucket = "existing-public-site"
  entity = "allAuthenticatedUsers"
  role   = "READER"
}
