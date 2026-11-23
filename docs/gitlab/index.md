# GitLab CI runner isolation

This guide is for GitLab and runner administrators responsible for pipelines that can access private resources or deploy. Settings and feature availability depend on your GitLab version and offering.

## Runner trust boundaries

Treat every job as code execution with the runner's network, filesystem and job credentials. Separate untrusted merge request workloads from protected deployment workloads using distinct runner pools, identities, networks and cloud permissions. Prefer disposable, single-job execution environments. Destroy the underlying compute after each job, including caches and workspaces that could carry state across trust levels. Container execution alone is not a complete host isolation boundary.

Mark deployment runners as protected, restrict their project or group scope and use protected branches and tags. Use runner tags for scheduling and protected runners for access control. Review who can modify pipeline configuration, protected refs, runner assignments and variables. Avoid shared shell executors and privileged containers for untrusted work. Never mount the host Docker socket into such jobs. Restrict egress and access to metadata services and internal production systems. See [runner security](https://docs.gitlab.com/runner/security/) and [protected runners](https://docs.gitlab.com/ci/runners/configure_runners/).

## Untrusted merge request pipelines

Run fork and other untrusted merge request code on isolated, disposable runners without protected variables, deployment credentials or production network access. Treat pipeline configuration, dependencies, caches and artifacts from that code as untrusted. Do not execute an untrusted artifact in a privileged deployment job merely because an earlier job produced it. Use separate cache namespaces and independently verify the provenance and integrity of promoted artifacts.

Review the project setting that allows merge request pipelines to access protected resources. When enabled, GitLab also requires both branches to be protected, both to belong to the same project, and the triggering user to have push or merge access to the target branch. Fork merge request pipelines cannot access those protected resources under this mechanism. Running a fork's pipeline in the parent project changes the execution context and can expose parent resources. Review the changes and GitLab's current [merge request pipeline guidance](https://docs.gitlab.com/ci/pipelines/merge_request_pipelines/) before doing so. Masked variables do not prevent malicious job code from sending their contents elsewhere.

## CI job token access

A `CI_JOB_TOKEN` is valid while its job runs and carries the triggering user's effective access within GitLab's supported job-token permissions. On the **target** project, keep the job token allowlist enabled and add only the source projects or groups that need access. An allowlist entry does not grant the triggering user additional permissions. Use fine-grained permissions where supported, and restrict public/internal feature visibility where necessary. Public features can remain accessible outside the allowlist. Review the [job token reference](https://docs.gitlab.com/ci/jobs/ci_job_token/) and [fine-grained permissions](https://docs.gitlab.com/ci/jobs/fine_grained_permissions/) for your version.

Record the owner and purpose of each cross-project entry, audit usage, remove stale access and avoid persistent personal tokens as a workaround. Restrict access to runner registration and authentication tokens independently of CI job tokens.

## Validation and recovery

Record current runner assignments, protection settings, job-token allowlists and affected dependencies before changing them. In a controlled test project, run harmless marker-only jobs for a protected branch, an ordinary branch and a fork merge request. Confirm the runner pool and protected-variable availability from job metadata and pass/fail markers without printing secret values. Test an authorized and an unauthorized source project against a harmless target resource, using the permissions of representative users. A denied request may reflect either the allowlist or the user’s permissions. Verify both. Test parent-project fork pipelines only after review and without sensitive resources.

Monitor runner registration and configuration changes, protected-ref and CI configuration changes, job-token authentication activity where available, and unexpected access failures. Alert on changes to deployment runner scope or privileged execution settings.

If isolation is suspected to have failed, pause the affected runner, stop or cancel affected jobs, preserve logs and evidence, and replace the underlying execution environment. Revoke and rotate any potentially exposed downstream credentials and runner authentication credentials through the appropriate GitLab procedure. Restore a reviewed runner configuration and the previous allowlist only where still justified. Rebuild a suspect runner from a trusted image. Re-run the validation matrix, verify dependent pipelines, and monitor for renewed access attempts.
