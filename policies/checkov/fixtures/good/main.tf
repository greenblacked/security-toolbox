resource "google_storage_bucket" "logs" {
  name                        = "example-logs"
  location                    = "EU"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "google_compute_firewall" "iap_ssh" {
  name          = "allow-iap-ssh"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_storage_bucket_iam_member" "reader" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:reader@example.iam.gserviceaccount.com"
}

resource "google_compute_firewall" "https_world" {
  name          = "https-world"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  allow {
    protocol = "tcp"
    ports    = ["80", "8443-8444"]
  }
}

resource "google_compute_firewall" "dns_udp_world" {
  name          = "dns-udp-world"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "udp"
    ports    = ["53"]
  }
}

resource "google_compute_firewall" "ssh_world_disabled" {
  name          = "ssh-world-disabled"
  network       = "default"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  disabled      = true

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
