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
