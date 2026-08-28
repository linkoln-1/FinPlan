# Security Policy

FinPlan is a local-first finance app: it stores financial data on the device
and makes no network requests. Even so, defects in data handling, backup
import/export, app locking or widget data sharing can have privacy impact, and
we treat them as security issues.

## Supported versions

| Version            | Supported |
|--------------------|-----------|
| `main` branch      | Yes       |
| Latest tagged 1.x  | Yes       |
| Older versions     | No        |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub's private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the issue, affected component, steps to reproduce and impact.

If private vulnerability reporting is unavailable for any reason, contact the
maintainer listed in [`.github/CODEOWNERS`](.github/CODEOWNERS) through GitHub
and ask for a private channel before sharing details.

Please **never include real financial data, backups, screenshots with real
amounts, credentials or device identifiers** in a report. Use synthetic data to
reproduce the problem.

## What to expect

- Acknowledgement within 7 days.
- An assessment and, where confirmed, a fix on a private branch.
- Coordinated disclosure: the fix is released before details are published,
  and reporters are credited in the changelog unless they prefer otherwise.

## Scope

In scope:

- Data exposure between the app, its widgets and exported files
- Bypasses of the app lock or balance-hiding features
- Crashes or data corruption triggered by crafted backup files
- Any unintended network activity

Out of scope:

- Issues that require a jailbroken device or physical access with an unlocked
  passcode
- Vulnerabilities in Apple frameworks that FinPlan uses as intended
