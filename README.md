# DeepSeek Usage

A macOS menu bar app that shows your DeepSeek API balance.

The header carries two badges: **Available** / **No balance** from the API's
`is_available` field, and the current pricing period — **Off-Peak** (green) or **Peak**
(red). Hover the pricing badge for the schedule and the next change.

## Peak and off-peak pricing

DeepSeek bills off-peak rates at half of peak rates:

> Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday
> (all other hours are off-peak).
> — [Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing)

The badge is computed in UTC from the system clock. Weekends are always off-peak.
The badge refreshes on the minute, so it flips at a window edge even when the
next balance poll is still minutes away.

## Does it consume my API usage?

**No.** The app makes exactly one kind of network request:

```
GET https://api.deepseek.com/user/balance
Authorization: Bearer <your key>
```

That is an account-metadata read. It runs no inference, so it produces no tokens and
bills nothing.

## Requirements

- macOS 14 or later (built and tested on macOS 26.2)
- Swift 6.2 toolchain — Command Line Tools are enough; full Xcode is not required
- A DeepSeek API key

## Build and run

```bash
./scripts/build-app.sh              # release build -> dist/DeepSeekUsage.app
open dist/DeepSeekUsage.app
```

Build a debug binary instead with `./scripts/build-app.sh debug`.

## Set your API key

Menu bar icon → **Settings** → paste the key → **Save & Test**.


`--check` additionally honours a `DEEPSEEK_API_KEY` environment variable, which takes
precedence and never touches the keychain.

## Command line

```bash
swift run DeepSeekUsage --check       # balance + current pricing period, then exit
swift run DeepSeekUsage --self-test   # offline checks of decoding, spend, and schedule
swift run DeepSeekUsage --render-preview preview-out
swift run DeepSeekUsage --version     # print the version and User-Agent
swift run DeepSeekUsage --help
```

The version is defined in exactly one place — the `VERSION` variable in
`scripts/build-app.sh`, baked into `CFBundleShortVersionString` and read back at runtime via
`AppInfo` — so it is never duplicated in source. A bare `swift run` binary has no bundle
`Info.plist` and reports `dev`; the same binary inside `DeepSeekUsage.app` reports the real
version.

`--check` exits `0` when the account is usable, `1` when the balance is exhausted or the
request failed, and `2` when no key is configured — handy for scripts and status bars. It
prints the current pricing period and the next change in UTC, which makes the schedule
logic inspectable without a UI:

```
$ DeepSeekUsage --check
pricing: off-peak now (peak hours: 01:00–04:00 and 06:00–10:00 UTC, Mon–Fri)
next change: peak at 2026-09-14T01:00:00Z
```

`--render-preview <dir>` snapshots the popover to PNG twice — once at a peak time and once
off-peak — using a fixed sample balance and no network. It exists so the visual states can
be reviewed without waiting for a particular hour (written to a gitignored directory, so
the snapshots stay out of the repository).

## Polling

Default is every 5 minutes; choose 30s to 1h in Settings. Changing it takes
effect immediately without a restart.

A failed refresh keeps the last good reading on screen and shows the error inline instead
of blanking the balance.

## Layout

```
Sources/DeepSeekUsageCore/     # no SwiftUI; unit-testable and reusable
  BalanceModels.swift          # lenient decoding of the balance payload
  BalanceClient.swift          # GET /user/balance + status-code mapping
  APIKeyStore.swift            # keychain storage, env fallback
  SpendTracker.swift           # balance-diff spend estimation
  PricingPeriod.swift          # peak / off-peak schedule (UTC, testable)
  UsageStore.swift             # observable state + refresh loop
  SettingsKeys.swift           # shared preference keys
  SelfTest.swift               # framework-free checks
Sources/DeepSeekUsage/         # the app
  main.swift                   # CLI dispatch, then the SwiftUI app
  DeepSeekUsageApp.swift       # MenuBarExtra + Settings scenes
  MenuContentView.swift        # the popover (badges, balance, actions)
  SettingsView.swift           # key + polling + caveats
Tests/DeepSeekUsageCoreTests/  # swift-testing suite (see note)
scripts/build-app.sh           # release build -> .app bundle
```

## Testing

```bash
swift run DeepSeekUsage --self-test   # works everywhere
swift test                            # only runs with full Xcode installed
```

A Command-Line-Tools-only Mac ships **no XCTest**, and the `Testing` module is off the
default framework search path, so the `swift-testing` suite in `Tests/` compiles to
nothing there (`#if canImport(Testing)`) and `swift test` reports zero tests rather than
failing. `--self-test` covers the same logic — 52 checks over money decoding, status-code
mapping, spend attribution, and the peak/off-peak schedule — with no test framework at
all.

## Uninstall

```bash
rm -rf dist/DeepSeekUsage.app
rm -rf ~/Library/Application\ Support/DeepSeekUsage   # estimated-spend state
# remove the key:  security delete-generic-password -s dev.locao.DeepSeekUsage
```
