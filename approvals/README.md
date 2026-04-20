# Approvals

This directory holds the **live, signed unlock approval artifact** consumed by
the Pocket Security Lab iSH gate.

## Files

When present, the directory contains:

- `current.json` — the compact, canonicalized approval JSON
  (schema: `pocket_lab_signed_approval_v1`).
- `current.json.sig` — detached ECDSA signature over `current.json`,
  produced with `keys/pocket_lab_github_approval_secp256k1.pub`'s
  corresponding private key (algorithm: `ECDSA-secp256k1-SHA256`).
- `current.json.sha256` — digest line for convenience.

## Regeneration contract

**These files are regenerated fresh per unlock** by the
`approve-pocket-lab-unlock-signed` workflow (see
`.github/workflows/approve-pocket-lab-unlock-signed.yml`). They must **never**
be checked in with a stale value:

- A committed `current.json` with `approved_at_utc == expires_at_utc`
  (zero validity) or a sentinel `nonce_sha256` equal to `sha256("")`
  (`e3b0c442…b855`) is broken and will be rejected by the
  `verify-approval` CI check.
- Between unlocks, this directory may be empty (no `current.json`) or may
  hold a placeholder artifact with `"approved": false`.

## Placeholder form

If a placeholder is required, use literally:

```json
{"schema": "pocket_lab_signed_approval_v1", "approved": false, "reason": "placeholder — regenerate via workflow_dispatch"}
```

with **no** accompanying `.sig` file. The `verify-approval` workflow skips
placeholder artifacts (`approved: false`).

## Verifying by hand

```
openssl dgst -sha256 \
  -verify ../keys/pocket_lab_github_approval_secp256k1.pub \
  -signature current.json.sig \
  current.json
```

Expect `Verified OK`.
