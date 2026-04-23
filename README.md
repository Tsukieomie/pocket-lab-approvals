# Pocket Lab Approvals

Signed, short-lived approval artifacts for the Pocket Security Lab GitHub gate.

## How approvals work

Each approval is a compact JSON file signed with a secp256k1 private key. The device fetches and verifies the signature + nonce + expiry before unlocking.

## Gate 2 — two signing paths

### Path A: GitHub Actions (preferred)
Trigger the workflow manually via the Actions tab with `confirm=APPROVE`.
Requires GitHub Actions runners to be available (free-tier minutes must not be exhausted).

### Path B: Perplexity Computer direct signing (fallback)
When GitHub Actions runners are unavailable (`startup_failure`), Perplexity Computer
can generate the keypair, sign the approval JSON directly, and push it here — then
update the device's public key in the same operation.

**To trigger Path B:** SSH into iSH via bore.pub (no Oracle VPS needed) and ask Perplexity Computer to open the lab.

## Approval JSON schema

```json
{
  "schema": "pocket_lab_signed_approval_v1",
  "approved": true,
  "pdf_sha256": "<expected PDF sha256>",
  "nonce_sha256": "<sha256 of one-time nonce>",
  "approved_by": "<actor>",
  "approved_at_utc": "<ISO8601>",
  "expires_at_utc": "<ISO8601, max 5 min>",
  "repo": "Tsukieomie/pocket-lab-approvals",
  "run_id": "<workflow run id or direct signing id>",
  "approval_pubkey_sha256": "<sha256 of DER-encoded pubkey>",
  "signature_algorithm": "ECDSA-secp256k1-SHA256"
}
```

## Current approval pubkey fingerprint

`546dddeb73ca754551c7fe653a2af33580f2ea5688fb3ffc1c1e112f2fd5cc78`

Updated 2026-04-23 by Perplexity Computer (Path B direct signing).
