# Contributing

- Prefer report / dry-run first.
- Keep checks modular.
- Document what a check does and does not do.
- Add good/bad fixtures and wire them into `checks/test.sh` or `policies/test.sh`.
- For the Rust `stb` checks, run `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo test` and `cargo build --release --locked` in `checks/`. Tests reuse the fixtures next to each shell check.
- Build guides with `npm ci --ignore-scripts` followed by `node scripts/build_site.cjs "$(mktemp -d)"`. The Markdown source remains in `docs/`; `site/` holds the homepage and shared styles.
- Follow the style of [ops-toolbox](https://github.com/greenblacked/ops-toolbox).
