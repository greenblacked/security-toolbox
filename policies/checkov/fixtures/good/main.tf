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

# Authoritative policy on an existing bucket, private members only.
data "google_iam_policy" "private_data" {
  binding {
    role    = "roles/storage.objectViewer"
    members = ["group:readers@example.com", "serviceAccount:reader@example.iam.gserviceaccount.com"]
  }
}

resource "google_storage_bucket_iam_policy" "existing_private" {
  bucket      = "existing-private-data"
  policy_data = data.google_iam_policy.private_data.policy_data
}

resource "google_storage_bucket_iam_policy" "existing_private_literal" {
  bucket = "existing-private-exports"
  policy_data = jsonencode({
    bindings = [{
      role    = "roles/storage.objectViewer"
      members = ["group:exports@example.com"]
    }]
  })
}

# Private identities whose names merely contain allUsers / allAuthenticatedUsers.
resource "google_storage_bucket_iam_member" "lookalike_group" {
  bucket = google_storage_bucket.logs.name
  role   = "roles/storage.objectViewer"
  member = "group:allUsers@example.com"
}

resource "google_storage_bucket_iam_binding" "lookalike_user" {
  bucket  = google_storage_bucket.logs.name
  role    = "roles/storage.objectViewer"
  members = ["user:allAuthenticatedUsers@x.com"]
}

resource "google_storage_bucket_acl" "lookalike_acl" {
  bucket      = google_storage_bucket.logs.name
  role_entity = ["OWNER:project-owners-123456", "READER:group-allUsers@example.com"]
}
