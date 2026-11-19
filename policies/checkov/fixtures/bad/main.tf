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
