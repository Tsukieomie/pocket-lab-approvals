# Pocket Lab v2.6 No-Token Signed GitHub Approval

This version avoids storing any GitHub personal access token in iSH.

## Security model

- GitHub Actions holds an Ed25519 approval signing key as a GitHub Actions secret.
- GitHub publishes only short-lived approval JSON + detached signature.
- iSH stores only the public approval verification key.
- iSH fetches approval files from a public/static URL and verifies signature locally.
- iSH still requires its local unlock secret to decrypt the lab.

## Why this is stronger

A GitHub read token on the phone is a bearer secret. If stolen, it grants repository access. v2.6 removes that phone-side token. A stolen public key or public approval file does not unlock anything unless the approval is signed, fresh, nonce-bound, PDF-hash-bound, and paired with the iSH local unlock secret.

## Required GitHub setup

Add a repository secret named:

APPROVAL_SIGNING_KEY_B64

Use the contents of docs/GITHUB_ACTIONS_SECRET_APPROVAL_SIGNING_KEY_B64.txt.

## Public approval feed

For no-token iSH fetch, approvals/current.json and approvals/current.json.sig must be accessible over HTTPS without authentication. Best options:

1. Separate public repo containing only approvals/ files.
2. GitHub Pages branch containing only approvals/ files.
3. Private repo plus a very small public mirror of signed approvals.

Do not publish unlock secrets or signing private keys.

Approval public key SHA-256:
6d79d6ca48496718229a5fb94c73809e2cdc4723e8e4c0bbf78dc50e66a9b61b
