# Secret Rotation

Rotate credentials with a planned or incident-specific procedure.

## Workflow

1. Decide whether this is planned rotation or an exposure incident. For an exposed credential, coordinate immediate containment instead of waiting for a normal rollout.
2. Inventory consumers and dependencies using access records and service owners. Where supported, issue a second credential and distribute it through an approved secret channel.
3. Roll consumers over and verify use of the replacement from provider telemetry after reporting lag. Disable the old credential, observe the bake period, then delete it.
4. Consider sessions or tokens already issued from the old credential and use platform-specific session controls where available. Monitor errors and authentication failures; retain a rollback plan for planned changes.

## Expected output and validation

A consumer inventory, replacement and cutover times, adoption evidence, old credential disablement and deletion status, session handling and validation results. Removing a secret from history does not revoke it.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
