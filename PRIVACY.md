# Privacy

This document describes how FinPlan handles data at a technical level. The user-facing privacy policy published for the app is available at <https://linkoln-1.github.io/finplan-legal/> and mirrored in [docs/privacy-policy.md](docs/privacy-policy.md).

## Summary

- FinPlan is local-first. All data is created, stored and processed on the device.
- The app makes no network requests. There is no backend, no account and no sign-in.
- There are no analytics, crash-reporting, advertising or tracking SDKs. The project has no third-party dependencies at all.
- Nothing is sold, shared or transmitted to anyone.

## Where data lives

| Data | Storage | Leaves the device? |
| --- | --- | --- |
| Accounts, transactions, goals, allocations, income sources, budgets, recurring templates, expected events, settings | SwiftData store inside the app's App Group container | No |
| Saved What-If scenarios | JSON file in the app's Application Support directory | No |
| Widget snapshot (primary goal progress, safe-to-spend amount, current-month totals) | `widget-snapshot.json` in the App Group container, read by the widget extension | No |
| Appearance preference | `UserDefaults` | No |

The App Group is used only so the app and its widget extension — two processes of the same app on the same device — can share files. It is not a sync mechanism.

## Network

The codebase contains no networking code: no `URLSession`, no sockets, no remote configuration, no fetching of exchange rates. Planning exchange rates are entered by the user by hand. If a future feature ever needs the network, it must be documented here and be opt-in.

## Exports and imports

- JSON backup and CSV export are created locally only when the user taps the corresponding action. The resulting file is handed to the system share sheet; where it goes from there (AirDrop, Files, another app) is the user's choice.
- Import reads a JSON file the user picks, validates it and shows a preview before anything is written.

Exports contain the user's full financial data. Treat them as sensitive.

## Authentication

App lock uses `LocalAuthentication` with the `deviceOwnerAuthentication` policy, so Face ID, Touch ID or the device passcode can unlock the app depending on what the device supports. The app receives only a success or failure result; biometric data never reaches the app and is never stored by it. If no authentication method is available the app does not lock the user out of their own data.

## On-screen privacy

- Hide-balances mode masks every amount in the interface (including charts) with a placeholder.
- When the app leaves the foreground, an overlay window covers the content so the app switcher shows no financial data.

## Notifications

All notifications are local (`UserNotifications`, scheduled on the device). No push notification service is used and no device token exists. Notifications can be disabled entirely or per type in Settings.

## Siri and widgets

App Intents run inside the app process on the device. Widgets read only the small snapshot file described above; they never open the database.

## iCloud

FinPlan does not sync to iCloud or CloudKit. Data exists only on the device where it was entered (and in any backups the user makes themselves, including device backups managed by iOS).

## Deleting data

- Settings offers a full reset that deletes every record and restores defaults.
- Uninstalling the app removes the app container, the App Group container and everything in them.

## For contributors

- Never commit real financial data, exports, screenshots of real data or device databases.
- Test fixtures and demo data must be synthetic.
- Any change that introduces network access, third-party code or off-device storage must update this document and be discussed in a pull request first.
