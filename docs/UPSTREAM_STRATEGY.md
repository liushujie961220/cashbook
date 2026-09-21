# Upstream Strategy

## Upstreams

- App: `TNT-Likely/BeeCount`
- Server: `TNT-Likely/BeeCount-Cloud`

Cashbook is for personal use and prioritizes low-maintenance customization over creating a new accounting engine.

## Integration rule

Cashbook changes are divided into three layers:

1. **Upstream core** — accounting, local DB, sync, shared ledger, Web UI.
2. **Cashbook capture layer** — Android notification gate, parser, candidate model and privacy controls.
3. **Cashbook experience layer** — two-person defaults, family dashboard, future shared goals/purchase plans.

The capture layer should not directly modify cloud synchronization internals.

## Update workflow

Before an upstream update:

1. Record the current upstream commit/tag.
2. Review upstream changes that touch Android platform services, transaction schema, local repositories or sync.
3. Re-apply Cashbook patches in the smallest possible patch set.
4. Run privacy checks before packaging.
5. Test two-device realtime sync.

## Things we intentionally do not inherit blindly

- Any feature that uploads raw OCR/payment text to a third-party AI service.
- Any always-on screenshot/media library monitor.
- Any analytics or crash SDK added upstream without review.
- Any new sensitive Android permission without a Cashbook privacy review.
