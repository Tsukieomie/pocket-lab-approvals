# Pocket Lab Public Signed Approvals

This repository is intentionally public so iSH can fetch signed approval files without storing a GitHub token.

It must never contain:

- iSH unlock secrets
- private signing keys
- GitHub tokens
- private lab contents
- plaintext lab files

It may contain:

- short-lived approval JSON files
- detached signatures for approval JSON files
- public verification keys
- GitHub Actions workflow for manual approval

The approval files are not secrets. iSH verifies them using a pinned public key and also requires the local iSH unlock secret before opening the lab.
