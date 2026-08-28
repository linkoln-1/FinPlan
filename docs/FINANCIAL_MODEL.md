# Financial Model

This document is the contract every contributor must respect when touching money code. All rules below are implemented in `Packages/FinPlanCore` and guarded by its test suite; if a rule and the code disagree, the tests decide and this document must be fixed.

## 1. Money and precision

- `Money` is an integer number of **minor units** (`Int64`, e.g. kopecks or cents) plus a `Currency`. There is no floating-point representation anywhere in the domain or the app's calculation paths.
- `Currency` carries the minor-unit exponent (0…6). `RUB`, `USD`, `EUR`, `GBP`, `CHF`, `CNY` use 2; `JPY`, `KRW`, `VND` use 0; `BHD`, `KWD`, `OMR` use 3; unknown codes default to 2.
- Addition, subtraction and comparison require the same currency and throw `MoneyError.currencyMismatch` otherwise. Overflow throws `MoneyError.overflow` (or traps in constructors, which are programmer errors).
- Multiplication by a fraction (`multiplied(byNumerator:denominator:)`) widens to `Int128`, divides, and rounds **half away from zero**. Results outside `Int64` trap.
- Basis points (1/100 of a percent, `10_000` = 100 %) are the unit for every ratio: personal income share, savings rate, budget fractions, milestones.

## 2. Exchange rates

- `ExchangeRate` is `base → quote` with a scaled integer: `rate = rateScaled / 10^scale`, `scale` 0…9 (default 6). `84.282` is stored as `84_282_000 / 10^6`.
- Decimal strings are parsed digit by digit; no floating point, no locale. More fraction digits than `scale` is a parse failure, not a rounding.
- `convert(_:)` multiplies minor units by `rateScaled` in `Int128`, adjusts for a different minor-unit exponent between currencies, then divides with half-away-from-zero rounding. `$4,000.00` at `84.282` is exactly `337,128.00 ₽`; `$6,250.00` is exactly `526,762.50 ₽`.
- `inverted` computes `10^(2·scale) / rateScaled` with the same rounding.
- `ManualExchangeRates` is the only provider in the app. Lookup order: identity when `base == quote` → a stored `base → quote` rate → the inverse of a stored `quote → base` rate → `nil`. A `nil` rate is an error at the call site (`LedgerError.missingExchangeRate`, `ProjectionError.missingPlanningRate`, …) that the UI shows with the missing pair; it is never silently treated as 1.
- Rates are user-maintained "planning rates". The app never fetches market rates.

## 3. Transactions

`TransactionRecord` has a `kind`, a `status`, an `amount`, optional `sourceAccountID` / `destinationAccountID`, optional `counterAmount` and `fee`, optional `categoryID` and `goalID`, `splits`, tags, a note and attachments.

### Kinds

| Kind | Required | Effect on balances |
| --- | --- | --- |
| `income` | destination | destination `+ amount` |
| `expense` | source | source `− amount` |
| `transfer` | source ≠ destination | source `− amount − fee`, destination `+ amount` |
| `currencyExchange` | source, destination, `counterAmount` in a different currency | source `− amount`, destination `+ counterAmount`, fee charged to whichever side matches its currency |
| `adjustment` | source or destination | destination `+ amount`, source `− amount` |

`validate()` enforces the table; amounts must be positive (except adjustments), transfers cannot target the same account, exchanges must carry a positive counter-amount in another currency.

### Invariants

- **Transfers and exchanges are neither income nor expense.** Moving money between your own accounts never changes totals, savings rate or net worth (apart from an explicit fee).
- **Fees are explicit.** A fee is its own field, attributed to exactly one account by currency. An exchange fee whose currency matches neither side is an error (`unattributableExchangeFee`), never a silent balance difference.
- **Goal-directed money is savings.** A transfer or expense with a `goalID` counts as `savingsAllocated`, not as spending. Category breakdowns and budgets exclude it.
- **Splits reconcile.** Split amounts must share the parent currency and sum exactly to the parent amount; category breakdowns and budgets honour splits.

### Status

`planned`, `expected`, `completed`, `skipped`, `cancelled`. **Only `completed` affects actual balances** (`status.affectsActualBalance`). Planned records generated from recurring templates and expected events exist for forecasting and never touch the ledger until confirmed.

### Periods

Every period is **half-open**: a transaction belongs to `[start, end)`. A transaction dated exactly on a boundary is counted once, in the later period. Balances "as of" a date include transactions dated `≤` that date.

## 4. Ledger

`LedgerEngine` is the accounting authority.

- `balance(of:transactions:asOf:)` = opening balance + effect of every completed transaction dated `≤ asOf` that touches the account.
- `periodSummary` over a half-open interval, converted to a reporting currency:
  - `income` — completed `income`
  - `expenses` — completed `expense` without `goalID`
  - `savingsAllocated` — completed `expense` or `transfer` with `goalID`
  - `fees` — transfer and exchange fees
  - `freeCashFlow = income − expenses − savingsAllocated`
- `categoryBreakdown` — completed expenses without `goalID`, split-aware, keyed by category (`nil` = uncategorised).
- `allocatedTotal(toGoal:)` — sum of `GoalAllocation`s for a goal dated `≤ asOf`, converted to the goal currency.

## 5. Net worth

`netWorth = Σ balance(account)` over accounts with `includedInNetWorth` and not archived, converted to the base currency; **credit accounts are subtracted** (`isLiability`). Archived accounts are excluded from every aggregate.

## 6. Savings rate

`savingsRateBasisPoints = round(savingsAllocated × 10_000 / income)` for the period, `nil` when income is not positive. Income here is realised external income only — transfers never inflate it.

## 7. Goals and allocations

- A `Goal` has a positive `targetAmount`, `startDate`, optional `desiredCompletionDate`, `priority`, `status` and an emergency-fund mode (`isEmergencyFund`, `desiredMonthsOfExpenses`).
- Goal funding is expressed by `GoalAllocation`s: explicit reservations of part of an account balance for a goal. `funded = allocatedTotal(toGoal:)`; progress in basis points is `funded / target`.
- **Double-allocation guard.** The unallocated balance of an account is `balance − Σ allocations on that account`. Adding an allocation larger than the unallocated balance is rejected (`overAllocation`), so the same money can never back two goals.
- The **primary goal** (dashboard, widgets, intents) is the active, non-emergency goal with the highest priority; ties are broken by earliest `startDate`, then by id.

## 8. Projection

`ProjectionEngine.project` simulates a goal balance cycle by cycle.

- A **cycle** is one calendar month from `startDate`, computed in a fixed UTC Gregorian calendar so results do not depend on the device time zone. Cycle 0 is the start; the date of cycle *n* is `startDate + n months`.
- Inputs: `startingAmount`, `target` (same currency), monthly `PlannedContribution`s (a day of month, clamped to the month's length, with an optional end date) or explicit dates, `PlannedOneTime` events (positive or negative, by cycle index or date), planning rates and a horizon (default 600 cycles).
- Contributions and events are converted to the goal currency **once**, up front, with the planning rates; a missing rate is `missingPlanningRate`.
- Each cycle `n ≥ 1` adds every active monthly stream, then any one-time amounts that fall in the cycle. A dated event lands in the first cycle whose date is `≥` the event date. The goal is reached at the first cycle whose end balance `≥ target`; the result carries `completionCycle`, `completionDate`, all points and — if not reached — `shortfallAtHorizon`.
- **Milestones**: standard percentages 10 / 25 / 50 / 75 / 90 / 100 % (thresholds computed in basis points with half-away-from-zero rounding) and arbitrary round amounts; each is the first cycle whose balance touches the threshold.
- **Required monthly contribution** for `cycles` months: `ceil((target − start − oneTime) / cycles)`; zero if the goal is already covered. Ceiling, never rounding, so a plan never undershoots.
- **Plan status**: `delta = actual − plannedByNow`; `ahead` / `onTrack` / `behind` by sign; `timeImpactDays = delta × 30 / monthlyPlannedContribution` (30 days per cycle for the day conversion).
- **Recovery plan**: `ceil(shortfall / remainingCycles)` extra per month to be back on plan by the desired date.

### Synthetic regression fixtures

These two scenarios are **synthetic test fixtures** (`ProjectionEngineTests`, `ScenarioEngineTests`), not real data. They pin the engine to exact integers:

- **Scenario A** — start `850,000.00 ₽`, target `6,000,000.00 ₽`, `$4,000.00` per month converted at `84.282` (`337,128.00 ₽`), plus a one-time `1,695,000.00 ₽` in cycle 6 → target reached in **cycle 11** with a balance of exactly `6,253,408.00 ₽`.
- **Scenario B** — same start and target, `$6,250.00` per month (`526,762.50 ₽`) → target reached in **cycle 7** at exactly `6,232,337.50 ₽`. The half-kopeck survives every cycle.

## 9. What-If scenarios

`ScenarioEngine` derives a `ProjectionInput` from a `ScenarioBasePlan` (starting amount, target, optional target date, income sources, monthly savings and its day, one-time events, planning rates, baseline monthly expenses) plus `ScenarioOverrides`:

- `incomeShareBps` per income source (0…10 000), `monthlySavingsAmount` **or** `savingsPercentBps` of total personal income, a `planningRate` override (replaces any stored rate for that pair in either direction), `extraOneTimeEvents`, `targetAmount`, `targetDate` (caps the horizon to whole months from start), `monthlyExpenseDelta`.
- `contribution = plannedSavings − monthlyExpenseDelta`, clamped at zero.
- `freeMonthly = totalIncome − contribution − baselineMonthlyExpenses − monthlyExpenseDelta`.
- `compare` projects the base plan and the scenario with identical machinery and reports both outcomes, cycles saved and the contribution delta. Applying a scenario never mutates the base plan.

## 10. Safe to Spend

```
raw       = liquidBalance − goalReserved − emergencyReserve − upcomingMandatory − minimumBuffer
available = max(raw, 0)
shortfall = −raw when raw < 0, otherwise nil
```

Every deduction must be non-negative (`negativeComponent` error). The result carries a breakdown with each component so the UI can explain the number.

How the app builds the input (in the base currency, through planning rates):

- `liquidBalance` — balances of non-archived accounts with `includedInSafeToSpend`.
- `goalReserved` — all goal allocations dated up to now. The emergency fund is an ordinary goal, so its reserve is already inside this sum and `emergencyReserve` is zero — nothing is counted twice.
- `upcomingMandatory` — planned occurrences of active, non-goal expense templates between now and the **next income date** (earliest occurrence of an income template or income source within 62 days; if none, a 30-day window).
- `minimumBuffer` — the user's minimum cash buffer setting.

## 11. Purchase impact ("Can I buy this?")

`PurchaseImpactEngine.evaluate` converts the purchase to the base currency and decides:

1. `purchase ≤ available` → **safe**; goal dates unchanged.
2. `purchase > liquidBalance` → **unaffordable**, with the shortfall.
3. `overflow = purchase − available`; if `overflow > goalReserved` → **touchesReserve** (the purchase would eat into the buffer / mandatory payments beyond what goals can absorb).
4. Otherwise → **delaysGoal**: the overflow is simulated as a negative one-time event on the purchase date in the goal projection. `goalDelayDays = ceil(overflow × 30 / tailMonthlyRate)` where the tail rate is the sum of monthly contributions still active at the original completion date; if there is no monthly stream, the delay is the difference in completion cycles × 30. `affectsNextMilestone` reports whether the next unreached percentage milestone moves later.

`remainingSafeToSpend` is always reported, computed as Safe to Spend with the purchase removed from the liquid balance.

## 12. Budgets

- A `Budget` is a positive amount for a category per `monthly` or `weekly` period with a rollover policy and `carriedOverMinor`.
- `spent` — completed expenses (or matching splits) in the category within the half-open period, excluding goal-tagged records.
- `available = amount + carriedOver`, `remaining = available − spent`, `fractionUsedBasisPoints = spent / available` (100 % if nothing is available and something was spent).
- `periodElapsedBasisPoints` is time elapsed in the period at second resolution.
- **Pace**: `hot` when `spent% > elapsed% + tolerance`, `ahead` when `spent% < elapsed% − tolerance`, else `onTrack`; default tolerance 500 bp.
- **Rollover** at period end: `expires` (carry 0), `rollsOver` (carry `max(unused, 0)`), `toGoal` / `toFreeCash` (carry 0 and release the positive unused amount to the destination).

## 13. Recurring templates and expected events

- Recurrences: `daily`, `weekly(weekday)`, `monthly(day)`, `yearly(month, day)`, `everyNDays(n)`. Monthly and yearly days are **clamped to the last day of shorter months** (a template on the 31st fires on Feb 28/29, Apr 30, …). Occurrences respect the template's `startDate`, optional `endDate` and the half-open query interval, and keep the template's time of day.
- `plannedRecords` materialises occurrences as `.planned` transactions carrying `recurringTemplateID`; they feed the calendar, Safe to Spend and notifications and never affect balances.
- Subscription equivalents for active expense templates: monthly `= amount × 365/12` (daily), `× 52/12` (weekly), `× 1` (monthly), `÷ 12` (yearly), `× 365/(12·n)` (every N days); yearly analogously.
- `ExpectedEvent` (bonus, payout, sale) has an amount, date, state (`expected`, `received`, `overdue`, `cancelled`) and an optional goal. `expected` events dated in the past and `overdue` events need attention; `received` and `cancelled` are inert. Upcoming goal-tagged events enter the goal projection as one-time inflows.

## 14. Analytics

- **Monthly summary** per calendar month (device calendar): income, expenses, savings, `netCashFlow = income − expenses`, savings rate.
- **Net-worth history**: net worth at each month end.
- **Runway** (months of essential spending covered): essential spending is the category breakdown over up to 6 fully covered past months restricted to categories marked `isEssential`; `runway = liquidFree × coveredMonths / totalEssential`, reported in tenths of a month; `nil` when fewer than two months of history or no essential spending exist; `0` when free liquid is not positive.
- **Monthly close**: the summary plus net worth at start and end, biggest expense category, and planned vs. actual income and expense variance.

## 15. Insights

`InsightEngine.evaluate` is rule-based and deterministic over an `InsightContext` snapshot: ahead / behind plan, goal or milestone reached, overspending category, unusual spending, upcoming large payment, expected income overdue, savings target missed or exceeded, low runway, low safe-to-spend, currency deviation from planning rates, recovery plan available. Each insight carries a severity (`info`, `attention`, `warning`), the values it was derived from and a textual basis; output order is independent of input order.

## 16. Errors are loud

Engines never guess. Missing rates, currency mismatches, negative deductions, invalid recurrences and overflow are thrown as typed errors and shown to the user with the offending pair or value. Do not add fallbacks that turn an error into a plausible-looking number.

## 17. Checklist for money changes

- Keep all arithmetic in `Money` / `Int64` / `Int128`; never introduce `Double` or `Decimal`.
- Preserve half-open periods and the "only completed affects balances" rule.
- Add or update a Swift Testing case for every behavioural change; extend the synthetic regression scenarios if the projection path changes.
- Use synthetic figures in fixtures. Never use real personal financial data.
