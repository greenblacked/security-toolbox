# Cloudflare Workers deployment security

This guide is for owners of Workers, their deployment pipelines and the zones they serve. Review changes in a non-production environment first.

## Deployment identity and environments

Use a dedicated API token for each deployment trust boundary. Grant the minimum Worker permissions and resource scope supported by your account. Route and custom-domain changes additionally need the relevant zone-level Workers Routes permission. Avoid granting zone access to a pipeline that only uploads code. Check the [Workers permissions reference](https://developers.cloudflare.com/workers/authorization/workers/) for the exact commands and resources in use. Keep the token in your CI secret manager, restrict the job and rotate it when its owner or trust boundary changes.

Define separate Wrangler environments and separate backing resources, credentials and deployment identities for staging and production. Review environment-specific bindings and routes explicitly. Check Wrangler’s inheritance rules for each setting. A version URL uses that version’s existing resources. Use a separate Wrangler environment for isolation. See [environments](https://developers.cloudflare.com/workers/wrangler/environments/) and [version URLs](https://developers.cloudflare.com/workers/versions-and-deployments/version-urls/).

## Routes, domains and public exposure

Inventory every route pattern, custom domain and `workers.dev` endpoint for each environment in the dashboard and Wrangler configuration. Verify which hostname and path reach each Worker and whether an origin can be reached separately. Disable unneeded public endpoints, and apply access controls to administrative surfaces. A Worker route, custom domain, DNS record and application authorization are separate controls. Verify all entry points after any of them changes.

Keep the inventory with the deployment record. Review route and DNS changes independently from code changes, including wildcard overlaps and zone ownership. Test authorization on each intended entry point with accounts you control.

## Secrets and assets

Store credentials as [Worker secrets](https://developers.cloudflare.com/workers/configuration/secrets/) or in an appropriate secret manager, not in source, Wrangler `vars`, static assets, logs or client-side JavaScript. Static assets are served to clients and must contain no credentials. Scope each secret to the environment and downstream permissions it needs. Verify bindings using secret names and keep values out of logs and output.

Secret changes can create a new Worker version and may deploy immediately. For gradual deployments, use the documented versions workflow and review the effective secret bindings before sending traffic. Rotate exposed credentials at the issuing service as well as in the Worker.

## Validation and recovery

Before deployment, record the current deployment/version IDs, traffic split, routes, domains, relevant bindings and downstream compatibility. Pin Wrangler through the project lockfile and confirm the installed version supports the commands used. From the Worker project directory, these read-only commands show deployment history for the selected environment:

```bash
./node_modules/.bin/wrangler deployments list --env production
./node_modules/.bin/wrangler versions list --env production
```

Use your actual Wrangler environment name. Omit `--env` only when the intended target is the default environment. After deployment, query an owned hostname and inspect status and response headers, then repeat for a representative static asset and a dynamic response.

```bash
curl --silent --show-error --dump-header - --output /dev/null https://YOUR_OWNED_HOST/
```

Replace the URL with the actual hostname and path. Check expected security headers, cache behavior and application health. Headers for static assets and Worker-generated responses may be configured separately. Probe each representative path. Confirm the active version and traffic split in deployment history and compare logs, error rate and latency with the pre-change baseline. Alert on unexpected deployment, route, domain and credential changes.

For an incident, use the [documented rollback procedure](https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/) to restore a known-good version after checking its bindings and compatibility. A rollback sends 100% of traffic to the chosen version, including when replacing a split deployment. Rollback may be blocked by deleted bindings or Durable Object lifecycle changes, and old versions may no longer be retained. Propagation takes time and clients may request assets from the newer version. A code rollback does not undo DNS, routes, external data migrations or downstream secret rotation. Restore those separately from the recorded state, coordinate any incompatible schema or credential change, and verify all entry points and health signals again. Test this recovery path in staging before relying on it.
