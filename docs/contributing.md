# Contributing

- Prefer report / dry-run first.
- Keep checks modular.
- Document what a check does and does not do.
- Add good/bad fixtures and wire them into `checks/test.sh` or `policies/test.sh`.
- Build docs with `mkdocs build --strict --site-dir "$(mktemp -d)"`; never build into `site/`, which holds the hand-written homepage.
- Follow the style of [ops-toolbox](https://github.com/greenblacked/ops-toolbox).
