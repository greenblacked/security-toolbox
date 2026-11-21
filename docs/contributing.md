# Contributing

- Prefer report / dry-run first.
- Keep checks modular.
- Document what a check does and does not do.
- Add good/bad fixtures and wire them into `checks/test.sh` or `policies/test.sh`.
- Write guides in `docs/` as Markdown. `node scripts/build_site.cjs` renders them into `site/`, which is gitignored for generated routes: commit the source, not the output.
- Skill procedures live in `plugins/security/skills/<name>/SKILL.md` and are published as written, so a change there is a change to the site. Reference files belong in `references/` beside them.
- Add a new page once, in the page table at the top of `scripts/build_site.cjs`. The build fails on a link to a route that does not exist, so a renamed page cannot ship a broken link.
- Run the checks before opening a pull request:

  ```bash
  npm ci --ignore-scripts
  node scripts/build_site.cjs
  python scripts/check_site.py site
  ```

- The site allows no inline scripts or styles: `site/_headers` sends a `script-src 'self'` policy. Put behaviour in a file under `site/`.
- Follow the style of [ops-toolbox](https://github.com/greenblacked/ops-toolbox).
