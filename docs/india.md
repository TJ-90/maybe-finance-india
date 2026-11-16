# India edition

This fork turns the app into a personal finance tracker for Indian households. This page lists what it does,
where its data comes from, and, most importantly, **what has not been verified against the real world**.
Read the caveats before you rely on a number.

> [!IMPORTANT]
> **After pulling an update, run `bin/rails db:migrate`.** The India features add tables and columns
> (securities, mutual fund schemes, goals, insurance policies and more). The app does not run migrations by itself.
> With Docker Compose, run `docker compose run --rm web bin/rails db:migrate`. The
> container entrypoint also runs `bin/rails db:prepare` whenever the Rails server starts, but do not rely on
> that alone: run the migration yourself and check that it succeeded.

## Features

| Area | What you get |
|---|---|
| Foundation | INR by default, lakh/crore grouping (`₹12,34,567`), `dd-mm-yyyy` dates, the April to March financial year, Indian account types and default categories. The product name comes from `PRODUCT_NAME`. |
| Bank and card statements | CSV import with bank presets (HDFC, ICICI, SBI, Axis, Kotak, IDFC FIRST, Yes, and card statements), separate debit and credit columns, and a parser for UPI, NEFT, IMPS, RTGS, NACH, ATM, card and cheque narrations (payment mode, counterparty, reference number). Known merchants get a category suggestion. |
| Investment import | CAMS/KFintech **CAS PDF** (detailed and summary, password-protected files, parsed on the server and never stored), the **Zerodha Console tradebook**, a best-effort generic broker layout, and a **mutual fund CSV template**. Imports are idempotent: re-importing a statement does not duplicate trades. |
| Market data | Mutual fund NAVs from AMFI/MFAPI, NSE/BSE prices from Yahoo Finance, USD/INR and other rates from Frankfurter, and a fund discovery page (filter by AMC, category, plan, option and active/passive). |
| Instruments | Fixed deposits, recurring deposits, NSC, KVP, SCSS, POMIS and corporate FDs with accrued value. EPF, VPF, PPF and SSY with interest posted from the rate table. Gold and silver by weight and purity. Insurance policies with premium reminders (kept out of net worth). Mutual funds with folio numbers, stocks and ETFs. |
| Net worth | A card that splits net worth into market assets (investments, FDs, gold), retirement funds (EPF/VPF/PPF/SSY and NPS), cash, property and vehicles, and other assets. Insurance is never part of net worth. |
| Returns | XIRR per holding, per account and for the whole portfolio. |
| Tax Center | FIFO lots per folio, LTCG/STCG classification, redemption-wise gains like a CAMS/KFintech capital gains statement, tax-harvesting suggestions up to the LTCG exemption, a sale simulator, per-family category overrides and CSV export. |
| Goals | Target corpus in today's money with inflation, SIP with yearly step-up, equity glide path, shortfall and required SIP, rebalancing hints, retirement corpus and an emergency fund goal. Holdings can be linked to goals by percentage. |
| AI assistant | Besides accounts, transactions, balance sheet and income statement, it can read your holdings (with XIRR), your goals and your realized gains for a financial year. |

## Data sources and how far to trust them

No Indian data source has been exercised against its live service during development: the build environment had no
network access to any of them. Providers were written from the documented formats and tested against hand-written
fixture payloads. **Treat the first live run as a test.**

| Source | Used for | Reliability notes |
|---|---|---|
| **AMFI `NAVAll.txt`** (`amfiindia.com/spages/NAVAll.txt`) | The list of every mutual fund scheme and its latest NAV, refreshed nightly by `ImportMutualFundSchemesJob`. | Official and public, but the parser is written from the documented semicolon layout and has only seen sample files. The URL, the column order or the category header wording can change. If a download ever imports zero schemes, nothing is overwritten. |
| **MFAPI** (`api.mfapi.in`) | NAV history for one scheme (`/mf/{scheme_code}`). | A free, community-run service with no uptime guarantee or published terms. The response format used here is from its public documentation. |
| **Yahoo Finance** (unofficial endpoints) | NSE (`.NS`) and BSE (`.BO`) prices and symbol search. | **Unofficial and undocumented.** The endpoints can change, rate limit or disappear without notice, and Yahoo's terms restrict commercial use. The provider is isolated behind `Provider::IndianMarkets` so it can be replaced (for example by NSE bhavcopy files or a paid feed). |
| **Frankfurter** (`api.frankfurter.app`) | Exchange rates from ECB reference data. | Free and keyless, but rates exist only for ECB working days (weekends use the previous working day) and only for the currencies the ECB publishes. |
| **Synth** (optional, `SYNTH_API_KEY`) | Prices and rates outside India, used as a fallback when configured. | Third-party and paid. Unrelated to the Indian sources. |

If a price cannot be fetched, a security is marked offline after repeated failures and keeps the last known value.
You can always record a price or valuation yourself.

To turn off every Indian source (and the nightly jobs that use them), set `DISABLE_INDIAN_MARKET_DATA=true`.
**Settings → Market data** shows which sources are active.

### Refreshing NAVs offline

If the server cannot reach AMFI:

1. On a machine that can, download `https://www.amfiindia.com/spages/NAVAll.txt` (save it as `NAVAll.txt`).
2. Open **Settings → Market data**, choose the file under "Upload NAVAll.txt" and press **Import schemes**
   (admin only).

This does exactly what the nightly job does: it updates every scheme and its latest NAV, records the NAV as a price
for the funds you hold, and links any fund that a CAS import had to keep under its ISIN to its scheme code. Repeat it
whenever you want fresh NAVs. NAV history for a fund (older than the latest NAV) still needs MFAPI.

## Tax Center disclaimer

**The Tax Center is indicative only and is not tax advice.**

- It does not compute surcharge, the 4% health and education cess, the Section 87A rebate, or carry-forward of
  unabsorbed losses.
- It treats each person's accounts as one taxpayer. Pick the accounts that belong to the same PAN, because the
  LTCG exemption is per person.
- Lots bought before 1 February 2018 would be grandfathered to their 31 January 2018 value. That value is not
  available, so the actual cost is used and a warning is shown.
- Indexation (for gains before 23 July 2024) is not computed.
- Fund categories (equity, debt, other) are inferred from AMFI category names. A wrong guess changes the tax
  treatment, so check the **Categories** tab and override a fund where needed.
- Rules live in `config/india_capital_gains.yml`, written from the Finance (No. 2) Act 2024 as the author understood
  it. **Verify them each financial year**, and before you act on any number, with a qualified tax professional.

The assistant is told not to give tax or investment advice, and the `get_tax_summary` function repeats the disclaimer.

## Rates and rules to verify

Every file under `config/` that holds a rule or rate has a "Verify" comment at the top. Update them when the
rules change; no code change is needed.

| File | Contents | Status |
|---|---|---|
| `config/india_small_savings_rates.yml` | EPF, PPF, SSY, NSC, KVP, SCSS and POMIS rates, effective-dated. | **Entered from memory of the published notifications and not checked against the latest notification.** Verify each quarter (EPF yearly). The FY 2025-26 EPF rate is a placeholder until EPFO declares it. A rate can be overridden per account, which always wins. |
| `config/india_capital_gains.yml` | Holding periods, LTCG/STCG rates, the Section 112A exemption (₹1.25 lakh from FY 2024-25) and Section 50AA debt-fund rules. | The pre-23-July-2024 rules for gold ETFs and other listed assets are approximations (the file says so). Verify each financial year. |
| `config/india_merchant_categories.yml` | Merchant names and the category they suggest. | A best-effort starting list. Suggestions only apply to rows with no category. |

## Bank, broker and CAS formats: what is confirmed and what is guessed

Statement layouts are not published by the banks and change without notice, and no real export could be checked
during development. The app labels each preset in the UI. A wrong preset costs one dropdown change, and nothing is
saved until you submit the configuration step.

### Bank and card CSV presets (`config/india_statement_presets.yml`)

| Preset | Status |
|---|---|
| HDFC Bank savings/current | **Confirmed** (column names from the reference exports used in the plan) |
| State Bank of India savings/current | Column names **confirmed**, the `1 Apr 2024` style date format is **unverified** |
| ICICI, Axis, Kotak, IDFC FIRST and Yes Bank savings/current | **Unverified**, best-effort recollection of each bank's export |
| HDFC, ICICI, SBI Card and Axis credit cards | **Unverified** |
| Generic (separate debit and credit columns) | **Unverified** |

Treat headers, date formats and sign handling of every "unverified" preset as a guess. Check the preview before
publishing an import. The narration parser (UPI, NEFT, ...) is also written from commonly seen formats; anything it
does not recognise keeps the original narration.

### Broker and fund templates (`config/india_broker_presets.yml`)

| Preset | Status |
|---|---|
| Zerodha Console tradebook | **Confirmed** (column names from the reference export) |
| Mutual fund transactions template | **Confirmed**, it is defined by this app. Download it from the import screen |
| Other broker (best-effort column match) | **Unverified** |
| Groww, Upstox, ICICI Direct, HDFC Securities, Kotak Securities, Angel One, Fyers, Aionion, Religare, 5paisa, Dhan | **Not shipped.** Use the plain trade import with its column mapping, or add a preset once you have checked a real export |

### CAMS / KFintech CAS PDF

The parser (`CasImport::Parser`) was written from public descriptions of the detailed and summary statements, **not
from real files**, and was tested only on synthetic text. Each line is matched on its own, so unknown lines are
ignored and anything that looks like a transaction but cannot be read is reported as a warning with its line.
Check every imported CAS against the units and values on the statement. Layout changes are likely to break parsing
before they produce wrong numbers, but wrong numbers are possible.

- PDFs are read in memory during the upload request; the file and its password are never stored.
- Text extraction uses `pdf-reader`. If a file uses an encryption it cannot handle and `qpdf` is installed, `qpdf` is used.
- Scanned (image-only) statements cannot be read.
- A fund that AMFI data does not know yet is kept under an offline security named after its ISIN. It is relinked to
  its scheme code when a later NAV import (nightly or the upload above) knows the scheme.
- A summary CAS has no history, so it creates one opening position per scheme at cost. XIRR and tax lots are then
  approximate. The import marks these rows.

## Environment variables

| Variable | Purpose |
|---|---|
| `PRODUCT_NAME` | The product name shown in the app, emails and the assistant. Defaults to the placeholder `Kosh`. |
| `DISABLE_INDIAN_MARKET_DATA` | `true` turns off AMFI, MFAPI, Yahoo Finance and Frankfurter. |
| `GITHUB_REPO` | `owner/repo` used for the changelog and feedback links (default `TJ-90/maybe-finance-india`). Empty hides both. |
| `SYNTH_API_KEY` | Optional. Prices and rates for markets outside India. |

## Demo data

`rake demo_data:default` loads an Indian household: an HDFC savings account with UPI/NEFT/NACH narrations, an ICICI
card, a Zerodha demat (RELIANCE, TCS, INFY, NIFTYBEES on NSE), three mutual funds with folio numbers, EPF, PPF, an FD,
a home loan, gold, a flat, two insurance policies and three goals. Log in as `user@example.com` / `password`.

The demo uses made-up mutual fund schemes (codes `900001` to `900003`) and seeds a price for every day, so generating
it never touches the network. Share prices follow a synthetic curve and are not real market history.

## Privacy

Everything runs on your own server. PDF statements and their passwords are processed in memory and discarded. Insurance
policy numbers are encrypted at rest. The only outbound requests are the market data lookups above, which send
scheme codes, ticker symbols and currency pairs, never amounts or names.
