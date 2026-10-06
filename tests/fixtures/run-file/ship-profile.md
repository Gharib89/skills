# Ship profile

Schema: 3

## Host

Host: github

## Local gate

Location: scripts/local-gate.sh
Tripwires: no raw SQL; no new dependency

## CI

Legs: bump-guard: the PR title is a Conventional Commit
Legs: lint: ShellCheck over the mechanics
No-checks legal: no

## Reviewers

### copilot

Login: copilot-pull-request-reviewer[bot]
Trigger: on-request

### claude

Login: claude[bot]
Trigger: on-request

## Verification

### github-mechanics

Proves: a changed mechanic performs its host call.
Applies when: the change touches the scripts.

### ado-mechanics

Proves: a changed adapter performs its host call.
Applies when: the change touches the adapter.

## Versioning and changelog

### not-a-verification

Text.
