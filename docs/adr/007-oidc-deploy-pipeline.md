# ADR 007: Production OIDC deploy pipeline (DESIGN-ONLY)

## Status
DESIGN-ONLY.

## Context
Production needs federated identity (OIDC) for CI/CD deploy roles instead of long-lived keys.

## Decision (target)
GitHub Actions OIDC → IAM role for plan/apply with environment protection rules.

## Why not built
Sandbox uses a single cloud_user identity; OIDC provider setup is out of session scope.

## Sandbox substitute
Local `make plan/apply` with explicit confirmation; static gates in GitHub Actions without apply.
