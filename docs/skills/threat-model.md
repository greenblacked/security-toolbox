# Threat Model

Model threats at the design stage.

## Workflow

1. Draw the data flows, actors, stores and trust boundaries for the proposed design. Identify who owns each crossing and what data is transferred.
2. Apply STRIDE to each relevant crossing and identify plausible failure modes. Focus on reachable paths and concrete assets rather than generic component lists.
3. Decide a mitigation or explicitly accept each meaningful risk with an owner. Define how each mitigation will be tested and how detection will reach a responder.
4. Review the model with design and operations owners, and revisit it when a trust boundary, identity, integration or data flow changes.

## Expected output and validation

A data-flow model, threats linked to crossings, mitigations and verification, owners and documented residual risks. Track open decisions through delivery.

## Related resources

[Browse all security skills](/skills/) · [Hardening guides](/#guides)
