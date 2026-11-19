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

# Private counterparts for every GCS ACL and IAM surface.

resource "google_storage_bucket_acl" "predefined_project_private" {
  bucket         = "existing-private-data"
  predefined_acl = "projectPrivate"
}

resource "google_storage_bucket_acl" "predefined_private" {
  bucket         = "existing-private-exports"
  predefined_acl = "private"
}

resource "google_storage_bucket_acl" "default_acl_bucket_owner" {
  bucket      = "existing-private-data"
  role_entity = ["OWNER:project-owners-123456"]
  default_acl = "bucketOwnerFullControl"
}

resource "google_storage_object_acl" "predefined_bucket_owner_read" {
  bucket         = "existing-private-data"
  object         = "export.csv"
  predefined_acl = "bucketOwnerRead"
}

resource "google_storage_object_acl" "role_entity_lookalike" {
  bucket      = "existing-private-data"
  object      = "report.pdf"
  role_entity = ["READER:group-allUsers@example.com"]
}

resource "google_storage_default_object_acl" "role_entity_lookalike" {
  bucket      = "existing-private-data"
  role_entity = ["OWNER:project-owners-123456", "READER:user-allAuthenticatedUsers@x.com"]
}

resource "google_storage_bucket_access_control" "group_entity" {
  bucket = "existing-private-data"
  entity = "group-allUsers@example.com"
  role   = "READER"
}

resource "google_storage_object_access_control" "project_entity" {
  bucket = "existing-private-data"
  object = "export.csv"
  entity = "project-viewers-123456"
  role   = "READER"
}

resource "google_storage_default_object_access_control" "group_entity" {
  bucket = "existing-private-data"
  entity = "group-readers@example.com"
  role   = "READER"
}

resource "google_storage_managed_folder_iam_member" "lookalike" {
  bucket         = "existing-private-data"
  managed_folder = "shared/"
  role           = "roles/storage.objectViewer"
  member         = "group:allUsers@example.com"
}

resource "google_storage_managed_folder_iam_binding" "lookalike" {
  bucket         = "existing-private-data"
  managed_folder = "shared/"
  role           = "roles/storage.objectViewer"
  members        = ["user:allAuthenticatedUsers@x.com"]
}

resource "google_storage_managed_folder_iam_policy" "private" {
  bucket         = "existing-private-data"
  managed_folder = "shared/"
  policy_data    = jsonencode({
    bindings = [{
      role    = "roles/storage.objectViewer"
      members = ["group:allUsers@example.com"]
    }]
  })
}
