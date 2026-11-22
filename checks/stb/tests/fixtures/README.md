# Test fixtures

`sarif-2.1.0.json` is a vendored copy of the SARIF 2.1.0 JSON schema from
<https://json.schemastore.org/sarif-2.1.0.json> (sha256
`c96eb2d311c37b0a38cbd18c52d79a68f778bbd2d831abed7412d9850740f785`). The tests
validate `stb --format sarif` output against it, so they never fetch anything.

The GKE cluster fixtures are not copied here; the tests read
`checks/gke/fixtures/` directly.
