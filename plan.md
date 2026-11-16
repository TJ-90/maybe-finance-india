# India Edition: Implementation Plan

This plan turns this fork of Maybe Finance into a personal finance app for Indian households. The feature set follows **NaviPlan** (https://fin.naviran.in, by Naviran Technologies with freefincal). The plan is written to be executed phase by phase by sub-agents. Every phase lists its files, schema changes, acceptance criteria and tests.

---

## 0. Context

### 0.1 What NaviPlan does (the reference product)

NaviPlan is a privacy-first, browser-only tracker and goal planner for Indian investors, priced at ₹2,500 a year. Its public feature set, taken from its homepage and the freefincal launch, FAQ and release posts (v1.1 "Terrace" through v1.6 "Seamount", Jun–Oct 2026):

| Area | NaviPlan feature |
|---|---|
| Import | CAMS/KFintech **CAS PDF import**, including password-protected PDFs, parsed locally. Excel template for manual or bulk transactions. **Broker tradebook upload** for Zerodha, ICICI Direct, HDFC Securities, Kotak, Angel One, Aionion, Fyers and Religare. NPS KFintech statement upload. |
| Valuation | Daily **NAV refresh**, with **NAVAll.txt upload** as a manual fallback. Fund discovery: browse every Indian MF scheme, filter by AMC, category, structure and active/passive, with latest NAV. |
| Returns | **XIRR** per holding and for the whole portfolio. Dashboard cards for invested amount, current value, total gain and XIRR. |
| Instruments | Mutual funds (incl. SIFs), stocks, FDs, RDs, gold, **EPF, PPF, NPS, SSY** (pension funds with auto-contribution tracking), insurance policies (term/health, kept out of net worth), and 9 currencies. |
| Goals | Goals (retirement, home, education…) with target corpus, date, inflation, SIP, SIP step-up and allocation preference. Map holdings to goals by percentage. Projected corpus, inflation-adjusted target, shortfall and required SIP. **Glide path** (equity de-risking) and **rebalancing** suggestions. Emergency-fund tracking. |
| Tax Center | **FIFO** lot simulation. **LTCG/STCG** classification. **Tax-harvesting** recommendations up to the ₹1.25 L LTCG exemption, at folio level, with gains netted per redemption as in the CAMS/KFintech capital gains statement. **Tax calculator** for a planned sale. **Category mapping** override. Indicative only: surcharge and cess are not computed. |
| Net worth | **Total Net Worth card**: market assets (MF, stocks, FD, RD, gold) + pension funds (EPF/PPF/NPS). Insurance is excluded. |
| Family | Multiple CAS files per household, labels per holding (whose fund is it), and per-person clubbing for the LTCG exemption. |
| Privacy | No cloud and no account. JSON backup/restore and Excel export. |

**Our version.** This fork stays a Rails app that people can self-host, which is its own privacy story. It keeps everything Maybe already does well (transactions, budgets, net worth history, rules, AI assistant, multi-currency) and adds NaviPlan's India-specific investment, tax and goal features.

### 0.2 About `morluto/rea`

`morluto/rea` ("Reverse Engineer Anything") is an MCP server for reverse-engineering binaries, apps and websites. It contains no finance or India code, so there is nothing in it to reuse. We also **will not** use it to decompile NaviPlan, which is a paid, proprietary product. Every feature here is built from public descriptions and public data formats (AMFI NAVAll.txt, CAS statement layout, broker CSV exports).

### 0.3 Legal and branding constraints (must follow)

- The upstream README says **"Maybe" is a trademark of Maybe Finance Inc. and may not be used by forks**, and neither may the logo. All user-facing "Maybe" text and logos must go (Phase 1). Ruby module and class names such as `Maybe::Application` can stay, because they are not user-facing.
- Keep the AGPLv3 license. The README must state that this is a fork of Maybe Finance and is **not affiliated with or endorsed by** Maybe Finance Inc.
- Do not use the NaviPlan or Naviran name, branding or copy in the product.
- The product name is a **placeholder**: `Rails.application.config.x.product_name = ENV.fetch("PRODUCT_NAME", "Kosh")`. The owner will choose the final name.

---

## 1. Ground rules for every phase

1. **Read `CLAUDE.md` first and follow it.** Skinny controllers and fat models in `app/models` (no `app/services`). Use `Current.family` and `Current.user`. Hotwire first. ViewComponents from `app/components/DS`. Use functional Tailwind tokens (`text-primary`, `bg-container`, `border-primary`). Use the `icon` helper, never `lucide_icon`. Hardcode English strings; do not add i18n keys. Write tests with Minitest, fixtures and mocha; never RSpec or factories.
2. **Minimize dependencies.** The only new gem this plan allows is `pdf-reader` (Phase 5, for CAS PDFs). Any other gem needs a written justification in the phase report, and you should prefer not to add one.
3. **Migrations.** `CLAUDE.md` says *"Do not automatically run migrations"*, so:
   - Write the migration file. Use your phase's timestamp block so parallel phases never collide: Phase N uses `20261117N0MMSS`, where N is the phase digit (Phase 2 → `20261117020001`, `20261117020002`, …).
   - **Hand-edit `db/schema.rb`** to match the migration exactly: tables in alphabetical order, indexes, `add_foreign_key` lines at the bottom, and `define(version: …)` set to the highest migration timestamp.
   - Never run `db:migrate`. Load the hand-edited schema into the test DB with `RAILS_ENV=test bin/rails db:schema:load` (that loads a schema, it does not run migrations). A schema that fails to load means your `schema.rb` edit is wrong.
4. **No network access to Indian data sources from this container.** `api.mfapi.in`, `amfiindia.com`, Yahoo Finance and `frankfurter.app` are all unreachable. Write providers against their documented formats and test them with **webmock/mocha stubs and hand-written fixture payloads** under `test/fixtures/files/`. Do not try to record VCR cassettes.
5. **No real personal data in fixtures.** CAS statements, bank statements and tradebooks used in tests must be synthetic: fake names, a PAN like `ABCDE1234F`, fake folio numbers.
6. **Money.** Use `Money` objects and the `format_money` / `format_money_compact` helpers (added in Phase 1). Format on the server, never in JS, except for chart tick labels.
7. **Tax and financial-rule data lives in YAML under `config/`** with effective dates, never inline in code. Add a `# Verify each financial year` header comment.
8. **Keep the suite green.** The baseline is 902 runs with 7 pre-existing errors, all caused by missing Plaid sandbox credentials (`test/models/provider/plaid_test.rb` ×6 and `UsersControllerTest#test_admin_can_reset_family_data`). Those 7 may stay red. Nothing else may.
9. **Commit early and often** on your phase branch, with clear messages. **Do not push**; the orchestrator merges and pushes.

### 1.1 Environment setup (already prepared in this container)

Ruby 3.4.4 cannot be downloaded here, so the container uses rbenv Ruby 3.3.6 with a copy of the Gemfile that has no Ruby pin. Postgres 16 and Redis are installed.

```bash
source /home/user/.maybe-dev/env.sh                # rbenv 3.3.6, BUNDLE_GEMFILE, DB creds; starts PG/Redis if down
export POSTGRES_DB=maybe_test_p<N>                  # one test DB per phase so parallel agents don't collide
RAILS_ENV=test bin/rails db:create db:schema:load   # first time, and after every schema.rb edit
bin/rails test                                      # full suite (~25s)
bin/rails test test/models/xirr_test.rb             # single file
bin/rubocop -f github -a
bundle exec erb_lint ./app/**/*.erb -a
bundle exec brakeman --no-pager -q --no-exit-on-warn   # bin/brakeman fails here (--ensure-latest); 1 pre-existing "Rails 7.2 EOL" warning is expected
```

- **System tests can't run in this container.** Chrome 153 is installed, but the only chromedriver is v147. Write system tests only where the plan asks for them, and say in your report that they weren't run. Every other test must pass.
- **Phase 1 conventions (now on the branch):**
  - Use `product_name` (helper) / `Rails.configuration.x.product_name` for the app name; never write "Maybe".
  - `Money.default_currency` is INR. Test fixtures in `families.yml` are pinned to USD/US, so pass currencies explicitly in tests.
  - Use `format_money_compact` for tight spaces.
  - FY periods: `Period.current_financial_year`, `Period.last_financial_year`, `Period.financial_year_for(date)`.
  - `Family#india?` exists.
- **Lint:** run rubocop as `bin/rubocop -f github -a app test config db/migrate lib`. Running it with no paths reformats `db/schema.rb`; don't commit that.
- **Fresh worktrees:**
  - Copy the gitignored `app/assets/builds/tailwind.css` from `/home/user/maybe-finance-india/app/assets/builds/` (read-only) if it's missing.
  - Check that `git log -1` is the latest commit of `claude/peaceful-darwin-s89wtn`. If it isn't, and you have no commits yet, run `git reset --hard claude/peaceful-darwin-s89wtn`.
- **Wave 2 integration surface (merged on the branch; use these names):**
  - **Phase 2:**
    - `Security::KINDS` / `ASSET_CLASSES` / `TAX_CATEGORIES` enums use prefixes (`kind_mutual_fund?`, `asset_class_equity?`, `tax_category_debt?`). `TAX_CATEGORIES = %w[equity debt other_listed other_unlisted exempt]`.
    - `Security::AMFI_MIC` / `NSE_MIC` / `BSE_MIC`, `Security#display_name`, and `#effective_tax_category(family)` / `#effective_asset_class(family)`, which honour the `FamilySecurityOverride` model.
    - `MutualFundScheme` (`.search`, `.discover`, `.import_navall!`; columns include `isin_growth`, `isin_reinvestment`, `tax_category`, `asset_class`).
    - `trades.folio_number`, `Provider::Registry#first_provider`.
    - `test/test_helper.rb` sets `DISABLE_INDIAN_MARKET_DATA=true` and loads `webmock/minitest`. Tests that need the providers wrap with `with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil`.
  - **Phase 3:**
    - Accountables `FixedDeposit`, `ProvidentFund`, `PreciousMetal`.
    - The generated-entries mechanism: `entries.generated_by` / `generated_user_edited` and `Account#replace_generated_entries!(source, specs)`, called from `Account::Syncer` via `generate_auto_entries!`.
    - `BalanceSheet::IndiaBreakdown` (`balance_sheet.india_breakdown`), and `InsurancePolicy`.
  - **Phase 4:**
    - `transactions.payment_mode` / `reference_number`, `Transaction::NarrationParser`, and `Transaction::MerchantHint`.
    - `Import` amount strategy `debit_credit_columns`, `Import.strip_preamble`, and `Import::StatementPreset` over `config/india_statement_presets.yml`. Use this preset pattern for broker presets.

- Never commit anything under `/home/user/.maybe-dev/`. Never change the `ruby file: ".ruby-version"` line in the repo `Gemfile`.
- **Adding a gem (Phase 5 only):** add it to the repo `Gemfile` *and* to `/home/user/.maybe-dev/Gemfile`, then run `bundle install`. Copy only the new gem's lines from `/home/user/.maybe-dev/Gemfile.lock` into the repo `Gemfile.lock`. `git diff Gemfile.lock` must show nothing but the new gem and its dependencies; the `RUBY VERSION` stays `ruby 3.4.4p34`.

---

## 2. Target data model (all phases combined)

| Change | Phase |
|---|---|
| `families` defaults → `currency: "INR"`, `country: "IN"`, `date_format: "%d-%m-%Y"`, `timezone: "Asia/Kolkata"` | 1 |
| `securities` + `kind` (stock/etf/mutual_fund/bond/gold/other), `isin` (indexed), `asset_class` (equity/debt/hybrid/gold/international/other), `tax_category` (equity/debt/other_listed/other_unlisted/exempt) | 2 |
| `mutual_fund_schemes` (scheme_code unique, name, amc, category, scheme_type, plan direct/regular, option growth/idcw, isin_growth, isin_reinvestment, latest_nav, nav_date, asset_class, active) | 2 |
| `trades` + `folio_number` (string, nullable, indexed with security_id) | 2 |
| `family_security_overrides` (family_id, security_id, tax_category, asset_class; unique [family_id, security_id]) | 2 |
| New accountables: `FixedDeposit` (fd, rd, nsc, kvp, scss, pomis, corporate_fd), `ProvidentFund` (epf, vpf, ppf, ssy), `PreciousMetal` (physical gold/silver) | 3 |
| `insurance_policies` (family-scoped, **not** an account) | 3 |
| `transactions` + `payment_mode` (upi/neft/imps/rtgs/card/atm/nach/cheque/cash/other, nullable) and `reference_number` | 4 |
| `CasImport`, `BrokerTradebookImport` import types | 5 |
| `goals`, `goal_allocations` | 7 |

---

## 3. Phases

### Phase 1: India foundation (localization, branding, defaults)

**Depends on:** nothing. **Runs:** alone, first.

1. **Rebrand (trademark).**
   - Add `config.x.product_name` (ENV `PRODUCT_NAME`, default `"Kosh"`) and a `product_name` helper.
   - Replace every user-facing "Maybe" in views, layouts, mailers, page titles, meta tags, onboarding, settings, `public/` PWA manifest and the AI assistant identity. Find them with `grep -rn "Maybe" app/views app/components app/mailers app/models/assistant config/locales public`.
   - Replace `app/assets/images/logo*.{svg,png}`, `public/*` favicons and the PWA icons with a neutral placeholder: a ₹ glyph in a rounded square. Author it as SVG. For the PNGs, render the SVG with the pre-installed Playwright Chromium: `require('playwright')`, screenshot an `<img>` at each size.
   - Rewrite the top of `README.md`: fork notice, "not affiliated with or endorsed by Maybe Finance Inc.", AGPLv3, and the India focus.
2. **Indian number formatting.**
   - INR must group as lakh/crore (`₹1,23,45,678.00`). In `lib/money/formatting.rb`, pass ActiveSupport's `delimiter_pattern: /(\d+?)(?=(\d\d)+(\d)(?!\d))/` when the currency is INR. Drive it from a new `number_grouping: indian` key in `config/currencies.yml` (inr) and expose it as `Money::Currency#indian_grouping?`.
   - Add `Money#format_compact`: `₹950`, `₹45.6K`, `₹12.35 L`, `₹1.20 Cr` for INR, falling back to `K/M/B` for other currencies. Add a `format_money_compact` helper. Use it in dashboard and summary cards where space is tight.
   - JS: grep `app/javascript` and `app/components` for `toLocaleString`, `Intl.NumberFormat` and `d3.format`. Make chart tooltips and axis ticks INR-aware (`Intl.NumberFormat("en-IN", …)` plus L/Cr compact ticks), with the currency passed in through a Stimulus value. The sankey chart currently hardcodes `toLocaleString(undefined…)` and a `$` default.
   - Set INR `priority: 1` in `currencies.yml` so it heads selectors and `Money::Currency.popular`.
3. **Defaults.**
   - Migration (`20261117010001`): change the `families` column defaults listed in §2. Update onboarding so country defaults to India, currency to INR, date format to `DD-MM-YYYY`, timezone to Asia/Kolkata, and put India first in the country list.
   - Add an `initializers/` setting so `Money.default_currency` is INR. Before keeping it, check it doesn't silently break tests that assume USD. If it does, fix those tests or leave the default and document why.
4. **Financial year (April–March).**
   - In `app/models/period.rb`, add `current_financial_year` (label_short `"FYTD"`, label `"Current FY (2026-27)"`, computed dynamically) and `last_financial_year` (`"Last FY"`).
   - Add `Period.financial_year_for(date)` and a `Date#financial_year_label`-style helper (no monkeypatching core; put it on `Period`).
   - Make FY options appear wherever period selectors are shown: dashboard cashflow, account charts and reports.
5. **Indian account subtypes.** Edit the `SUBTYPES` hashes.
   - `Depository`: savings, current, salary, nre, nro. Keep the old keys used by fixtures, or update the fixtures.
   - `Investment`: demat, mutual_fund, nps_tier1, nps_tier2, ulip, pms_aif, brokerage, angel. Remove the US 401k/IRA/529/HSA entries and update the tests that reference them.
   - `Loan`: home, vehicle, personal, education, gold, loan_against_property, other.
   - `Property`: residential, commercial, plot, agricultural.
6. **Indian default categories.** Edit `Category.default_categories`.
   - Income: Salary, Business Income, Interest, Dividends, Rental Income.
   - Expense: Rent & Housing (incl. society maintenance), Utilities (electricity, water, LPG, mobile, broadband, DTH), Groceries, Food Delivery & Dining, Transport & Fuel (fuel, cab/auto, metro/rail, FASTag/tolls), Shopping, EMI & Loan Payments, Insurance Premiums, Investments & SIP, Healthcare, Education & School Fees, Domestic Help, Personal Care, Entertainment & OTT, Travel, Gifts & Festivals, Donations, Taxes (TDS / Advance Tax), Bank Charges & Fees.
   - Use existing lucide icon names only.
7. **Hide unavailable US-only integrations.** Plaid doesn't serve India. When `family.country == "IN"` or Plaid isn't configured, the account "method selector" shows only manual entry and import (`app/views/accounts/new/_method_selector.html.erb`). Stripe billing and Intercom stay hidden unless their ENV vars are set; verify they already behave this way.
8. **AI assistant identity.** In `app/models/assistant/configurable.rb`, use the product name, mention India context (INR, lakh/crore, FY April–March, Indian instruments), and state that it gives no tax or investment advice. Keep the rest of the prompt.

**Acceptance criteria**
- `Money.new(12345678.9, "INR").format` returns `"₹1,23,45,678.90"`. `format_compact` gives `"₹1.23 Cr"`, `"₹12.35 L"` and `"₹45.6K"` for the matching magnitudes. USD output is unchanged.
- A new family defaults to INR, IN, `%d-%m-%Y` and Asia/Kolkata.
- `Period.current_financial_year` on 2026-11-16 covers 2026-04-01..2026-11-16, and on 2027-02-10 covers 2026-04-01..2027-02-10.
- No user-facing "Maybe" string or logo remains (excluding `LICENSE`, the README attribution and code identifiers).

**Tests:** money formatting (INR full and compact, USD unchanged), `Period` FY keys around the April boundary, family defaults, an updated category bootstrap test, and an updated subtype label test.

---

### Phase 2: Indian market data (MF NAVs, NSE/BSE prices, FX) + fund discovery

**Depends on:** Phase 1. **Runs:** in parallel with Phases 3 and 4.

1. **Schema** (`2026111702xxxx`): the `securities` columns, `mutual_fund_schemes`, `trades.folio_number` and `family_security_overrides` from §2. Add model validations and enums using `enum … validate: true`, the existing pattern. Add `Security#effective_tax_category(family)` and `#effective_asset_class(family)`; both honour `family_security_overrides`.
2. **Providers** in `app/models/provider/`. Each subclasses `Provider`, uses `with_provider_response`, and follows `Provider::Synth`'s structure.
   - `Provider::Amfi`:
     - Fetches `https://www.amfiindia.com/spages/NAVAll.txt` and parses it. Lines look like `Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date`.
     - Section headers (`Open Ended Schemes(Equity Scheme - Large Cap Fund)`) set the category. Bare AMC-name lines set the AMC.
     - Infers plan (Direct/Regular) and option (Growth/IDCW) from the scheme name, and `asset_class` from the category: Equity → equity, Debt → debt, Hybrid → hybrid, "Gold"/"Silver" in the name → gold, "International"/"Overseas"/"FoF Overseas" → international.
     - Infers `tax_category` from the category: equity schemes and Arbitrage/Equity Savings/Aggressive Hybrid (≥65% equity) → equity; debt and liquid → debt; others → other_unlisted; ETFs with listed units → other_listed unless equity.
     - Exposes `parse_navall(io)` publicly, so the manual upload fallback reuses it.
   - `Provider::Mfapi` (`SecurityConcept`):
     - Uses `https://api.mfapi.in/mf/{scheme_code}`, which returns JSON `{meta:{scheme_name,…}, data:[{date:"dd-mm-yyyy", nav:"123.45"}]}`, for historical NAV.
     - Search goes against the local `mutual_fund_schemes` table, not the network.
     - MF securities use `ticker = scheme_code` and the pseudo-MIC `exchange_operating_mic = "AMFI"` (constant `Security::AMFI_MIC`), with `country_code = "IN"` and `kind = mutual_fund`.
   - `Provider::YahooFinance` (`SecurityConcept`):
     - Covers NSE (`XNSE` → `.NS` suffix) and BSE (`XBOM` → `.BO`) stocks, ETFs and SGBs.
     - Uses chart `https://query1.finance.yahoo.com/v8/finance/chart/{sym}?period1=…&period2=…&interval=1d` and search `https://query2.finance.yahoo.com/v1/finance/search?q=…`.
     - Sends a browser-like User-Agent. Comments must warn that this API is unofficial and may break. Keep the provider small so it can be swapped out.
   - `Provider::Frankfurter` (`ExchangeRateConcept`): `https://api.frankfurter.app/{date}?from=USD&to=INR` and `/{start}..{end}`. It is free, keyless and uses ECB data.
   - `Provider::IndianMarkets`: a composite `SecurityConcept` that routes by `exchange_operating_mic` (AMFI → Mfapi, XNSE/XBOM → Yahoo). Search merges local MF results with Yahoo equity results.
   - `Provider::Registry`: `securities` → `%i[indian_markets synth]`, `exchange_rates` → `%i[frankfurter synth]`. Change `Security::Provided.provider` and `ExchangeRate` provider lookup to use the **first configured** provider instead of hardcoding `:synth`. The Indian providers are enabled by default and can be disabled with ENV `DISABLE_INDIAN_MARKET_DATA=true`.
3. **Jobs and schedule** (`config/schedule.yml`, cron in UTC):
   - `ImportMutualFundSchemesJob` at `0 18 * * *` (23:30 IST, after AMFI publishes NAVs). It upserts schemes and latest NAVs, and writes today's `Security::Price` for MF securities already in use.
   - Move `import_market_data` to `30 18 * * *` (00:00 IST).
   - Update the descriptions to IST.
4. **NAVAll.txt manual upload (offline fallback).** Add a section to *Settings → Hosting* (or a new *Settings → Market data* page) where the user uploads a NAVAll.txt. It is parsed with `Provider::Amfi.parse_navall` and the schemes and NAVs are upserted. Show the last NAV date. The page also shows provider status (configured, last sync) and replaces or labels the Synth key UI.
5. **Fund discovery** (`/mutual_funds`, `MutualFundsController#index` / `#show`):
   - Search by name, AMC filter, category filter, plan (direct/regular), option (growth/IDCW), and active/passive (index fund or ETF by name).
   - Paginated with `pagy`; columns are name, AMC, category, latest NAV and NAV date.
   - The show page has a NAV history chart (fetched via `Provider::Mfapi`, cached into `security_prices`) and an "Add to an investment account" action that pre-fills the trade form.
   - Add a desktop nav item "Funds" (icon `search`).
6. **Trade form.** The security combobox (`SynthComboboxOption` / `securities_controller`) must find MFs by name and NSE/BSE symbols. Show a kind badge (MF / NSE / BSE). Holdings tables show the scheme name for MFs instead of the numeric ticker.

**Acceptance criteria**
- Parsing a 30-line synthetic NAVAll fixture gives the right schemes, AMC, category, plan, option, asset class and tax category.
- A trade on an MF security gets historical prices through `MarketDataImporter` with stubbed MFAPI responses, and the holding values correctly.
- With an NSE security and stubbed Yahoo chart JSON, prices import.
- USD→INR rates import from stubbed Frankfurter.
- The fund discovery page renders and filters (controller test).
- NAVAll upload works (controller or model test).

---

### Phase 3: Indian instruments (FD/RD, EPF/PPF/SSY, NPS, gold, insurance) + net worth card

**Depends on:** Phase 1. **Runs:** in parallel with Phases 2 and 4.

New accountables follow the existing pattern end to end, using `Vehicle` and `Property` as templates: model with `include Accountable`, `SUBTYPES`, color, icon and classification; added to `Accountable::TYPES`; controller using the `AccountableResource` concern; routes; `app/views/<type>/` (`_form`, `new`, `edit`, tabs/overview); account-type picker entry in `accounts/new`; sidebar grouping; fixtures; tests.

1. **`FixedDeposit`** (`20261117030001`).
   - Subtypes: fd, rd, nsc, kvp, scss, pomis, corporate_fd.
   - Fields: `interest_rate` (decimal, % p.a.), `compounding` (monthly/quarterly/half_yearly/yearly/simple), `payout` (cumulative/monthly/quarterly/yearly), `start_date`, `maturity_date`, `monthly_installment` (RD), `institution_name`, `auto_renew` (bool).
   - `FixedDeposit#value_on(date)` implements the Indian bank formulas. FD: `P·(1+r/n)^(n·t)`, quarterly compounding by default. RD: quarterly-compounded sum over installments. Payout FDs keep principal flat and generate interest-income entries.
   - `FixedDeposit::Accruer` runs during account sync. It (re)generates month-end **auto valuations** idempotently: mark them so they can be deleted and recreated, either with a `kind` column on valuations or another explicit marker. Never touch user-entered valuations. After maturity the value freezes, or rolls over when `auto_renew`.
2. **`ProvidentFund`** (`20261117030002`).
   - Subtypes: epf, vpf, ppf, ssy.
   - Fields: `interest_rate` (defaults from `config/india_small_savings_rates.yml`, editable), `monthly_contribution`, `employer_contribution` (EPF), `opened_on`, `maturity_date`, `account_number_last4`.
   - Contributions are ordinary transactions or transfers into the account. `ProvidentFund::InterestCalculator` computes annual interest:
     - EPF: monthly running balance × rate/12, credited at FY end (31 March).
     - PPF and SSY: interest on the lowest balance between the 5th and the month end, approximated as the balance on the 5th, credited 31 March.
   - Interest is written as idempotent auto entries, the same mechanism as the FD accruer.
   - `config/india_small_savings_rates.yml` holds effective-dated rates for PPF, SSY, NSC, KVP, SCSS, POMIS and EPF. Use the latest rates you know, with a `# Verify each quarter` comment; they are user-overridable per account.
   - **NPS** is *not* a ProvidentFund. It is an `Investment` subtype (`nps_tier1` / `nps_tier2`, from Phase 1) valued by manual valuations for now; NPS statement parsing is listed under Later.
3. **`PreciousMetal`** (`20261117030003`).
   - Subtypes: gold, silver.
   - Fields: `weight_grams`, `purity` (24k/22k/18k/999/925), `form` (coins/bars/jewellery).
   - The balance comes from valuations. The form offers "price per gram × weight × purity factor", which creates a valuation.
   - Gold ETFs, gold MFs and SGBs stay as securities inside investment accounts (asset_class gold).
4. **Insurance policies** (`20261117030004`). This is **not** an account.
   - `insurance_policies`: family_id, kind (term/health/life/ulip/vehicle/home/other), insurer, policy_number (use ActiveRecord encryption, as other sensitive fields in the app already do), insured_names, sum_assured (money), premium (money), premium_frequency, next_premium_due_on, start_date, end_date, nominee, notes. Policy documents attach through ActiveStorage.
   - CRUD under `/insurance_policies`, reachable from Settings or the account sidebar.
   - The dashboard shows "Upcoming premiums (next 30 days)".
   - Excluded from net worth.
5. **Net worth breakdown card** on the dashboard. `BalanceSheet#india_breakdown` (or a clearly named PORO under `app/models/balance_sheet/`) returns:
   - Market assets: Investment except NPS, FixedDeposit, PreciousMetal, Crypto.
   - Retirement funds: ProvidentFund and NPS subtypes.
   - Cash: Depository.
   - Property & vehicles.
   - Other.
   - Liabilities.
   - Net worth.
   Render it with `format_money_compact`. The card only shows when the family has any market or retirement asset.

**Acceptance criteria**
- An FD of ₹1,00,000 at 7% compounded quarterly for 1 year values at ₹1,07,186 (±₹1).
- An RD of ₹5,000/month at 6.5% for 12 months matures at ≈ ₹62,144 (standard formula Σᵢ P·(1+r/4)^(4·i/12), i = 1..12). Assert it in a test, within ₹1.
- The PPF interest calculation for a sample year matches a hand-computed value.
- Re-running sync never duplicates auto entries.
- Insurance CRUD controller tests pass.
- The dashboard renders with the new card.

---

### Phase 4: Indian bank and credit-card statement import + UPI intelligence

**Depends on:** Phase 1. **Runs:** in parallel with Phases 2 and 3.

1. **Debit/credit column strategy.** Indian statements put withdrawals and deposits in separate columns. Add `debit_credit_columns` to `Import::AMOUNT_TYPE_STRATEGIES`, with `debit_col_label` / `credit_col_label` columns on `imports` (`2026111704xxxx`). Wire it through `Import::Row` amount derivation and the configuration UI (`app/views/import/configurations/`).
2. **Preamble skipping.** Bank CSVs have account-info lines above the header. Add `header_row_detection`: skip lines until a row contains the expected header tokens. Do it in `Import#parsed_csv` behind a per-preset flag, or generically by finding the first row with ≥3 non-empty cells that matches the configured date column label.
3. **Bank presets** in `config/india_statement_presets.yml`, offered as a "Bank" select on the import configuration step that pre-fills column labels, date format, number format, amount strategy and header detection. Presets:
   - Savings: HDFC, ICICI, SBI, Axis, Kotak, IDFC FIRST, Yes Bank.
   - Credit card: HDFC, ICICI, SBI Card, Axis.
   - Generic.
   Write one synthetic fixture per preset you implement, following the bank's export column names (e.g. HDFC: `Date, Narration, Chq./Ref.No., Value Dt, Withdrawal Amt., Deposit Amt., Closing Balance`; SBI: `Txn Date, Value Date, Description, Ref No./Cheque No., Debit, Credit, Balance`). Where you are unsure of a bank's exact headers, implement it as configurable and say so in the report. Do not invent certainty.
4. **Narration parser.** `Transaction::NarrationParser`, a PORO in `app/models/transaction/`, takes a raw narration and returns `{ payment_mode:, counterparty:, vpa:, reference_number:, clean_name: }`. Handle:
   - UPI (`UPI-SWIGGY-swiggy@icici-ICIC0000001-412345678901-UPI`, `UPI/412345678901/DR/Swiggy/…`).
   - NEFT/IMPS/RTGS (`NEFT CR-…-ACME PVT LTD-…`).
   - NACH/ACH (SIP and EMI debits such as `ACH D- BSE LIMITED-…`, `NACH-MF-…`).
   - POS / card, ATM (`ATW-`, `NWD-`), cheque, interest credit (`INT.PD`, `Int.Pd`), bank charges.
   Apply it during `TransactionImport#import!` to set `name`, `payment_mode`, `reference_number` and the merchant (find-or-create `FamilyMerchant` by normalized counterparty).
5. **Default merchant → category hints.** Add `config/india_merchant_categories.yml`. Examples: Swiggy/Zomato → Food Delivery & Dining; BigBasket/Blinkit/Zepto/DMart → Groceries; Uber/Ola/Rapido/IRCTC → Transport; Airtel/Jio/Vi/ACT/BESCOM/Tata Power → Utilities; Netflix/Hotstar/Spotify → Entertainment; Amazon/Flipkart/Myntra → Shopping; LIC/HDFC Life/Star Health → Insurance Premiums; BSE Limited / NSE Clearing / MF utilities / ICCL → Investments & SIP.
   Apply the hints only when the transaction has no category and the user hasn't locked it. Reuse the existing `enrich_attribute` / `locked_attributes` mechanism; do not override rules or AI categorization.
6. **UI.** Transaction list and detail show the payment mode as a small badge (UPI/NEFT/…). Transaction search gains a payment-mode filter.

**Acceptance criteria**
- Each implemented preset imports its synthetic fixture with correct signs and amounts.
- The narration parser has table-driven tests covering ≥15 narration samples.
- Merchant hints categorize the sample imports.
- Existing import tests stay green.

---

### Phase 5: Investment imports (CAS PDF, broker tradebooks, MF template)

**Depends on:** Phase 2 (securities, `mutual_fund_schemes`, `trades.folio_number`, ISIN). **Runs:** in parallel with Phases 6 and 7.

1. **Gem.** Add `pdf-reader` (pure Ruby, long-lived, MIT). Justification: CAS PDF import is NaviPlan's central feature and Rails has no PDF text extraction. Follow the procedure in §1.1. Check that it decrypts password-protected CAS PDFs; CAMS and KFintech use the investor's PAN, or the password the investor set on MFCentral or CAMS. If the encryption isn't supported, fall back to the `qpdf` CLI when it's installed, and otherwise show a clear error asking for an unlocked PDF.
2. **`CasImport < Import`.**
   - Upload the PDF plus password. Extract text **synchronously in the request**, then discard the PDF and the password: never persist them, never pass them to a job.
   - `CasImport::Parser` turns the text into investors (name, masked PAN `XXXXX1234X`), folios (AMC, folio number), schemes (name, ISIN, AMFI code if present, registrar), transactions and closing balance/valuation. It is written against **text** so tests use synthetic `.txt` fixtures.
   - Support CAMS and KFintech **detailed** CAS: dates like `12-Jan-2024`, amounts with commas, parentheses for negatives, and transaction types purchase, SIP / systematic investment, redemption, switch in/out, dividend reinvestment / IDCW reinvest, dividend payout, reversal, and `*** Stamp Duty ***` / `*** STT Paid ***` lines (attached to the parent transaction, not imported as trades).
   - **Summary** CAS (holdings only) imports one opening position per scheme at cost value. Flag it as "no transaction history; XIRR and tax lots approximate".
   - Mapping step: CAS investor → existing or new Investment account (subtype `mutual_fund`, default name "Mutual Funds – <first name>"). Each scheme resolves via ISIN → `mutual_fund_schemes` → `Security` (kind mutual_fund, ticker scheme code, MIC AMFI), creating the Security if needed. Unknown ISINs become an offline security with the scheme name.
   - Publish creates `Trade`s with `folio_number`, price = NAV, qty = units (negative for redemptions or switch-outs) and amount from the CAS.
   - **Re-import is idempotent**: skip a transaction when a trade with the same (account, security, folio_number, date, qty) exists. Show "N new, M already imported" on the confirm step.
   - Views follow the existing import flow (`app/views/imports`, `app/controllers/import/*`). Add a "Mutual fund CAS (PDF)" card to `imports/new`.
3. **`BrokerTradebookImport`** (a TradeImport subclass or preset system) with `config/india_broker_presets.yml`.
   - Implement **Zerodha Console tradebook** fully: `symbol, isin, trade_date, exchange, segment, series, trade_type, auction, quantity, price, trade_id, order_id, order_execution_time`. Exchange NSE → XNSE, BSE → XBOM. Sell → negative qty. Resolve the security by ISIN first, then by symbol + MIC via `Security::Resolver`. Dedupe on `trade_id`, stored as a trade-level reference: add `trades.external_id` in a `2026111705xxxx` migration if needed.
   - Add presets for Groww, Upstox, ICICI Direct, HDFC Securities, Kotak, Angel One and Fyers **only where you know the column layout with confidence**. Otherwise leave a documented generic mapping and list them as TODO in the report.
4. **MF manual template.** Add a TradeImport CSV template for demat or manual MF transactions: `date, scheme_code or isin, folio, units, nav, amount, type`.

**Acceptance criteria**
- Parser tests on ≥2 synthetic CAS texts (CAMS-style and KFintech-style) produce the expected investors, folios, schemes, transactions and closing units. Units after import equal the CAS closing units.
- Re-importing creates 0 duplicates.
- A Zerodha fixture imports buys and sells with correct signs and MICs.
- The PDF extraction layer is tested with a tiny generated PDF, or stubbed, with no real statements.

---

### Phase 6: Returns (XIRR) and Tax Center

**Depends on:** Phase 2 (`folio_number`, `tax_category`, overrides). **Runs:** in parallel with Phases 5 and 7.

1. **`Xirr`** (`app/models/xirr.rb`): Newton-Raphson with a bisection fallback. Input is `[(date, amount)]` with outflows negative. Returns `nil` when it doesn't converge or every flow has the same sign.
   - `Account#xirr` and `Holding#xirr` use trade cash flows plus the current value as a terminal inflow on today's date. `Family#portfolio_xirr(accounts: …)` does the same across accounts.
   - Show XIRR on the investment account overview, the holdings table (new column) and an "Investments" dashboard card with Invested, Current value, Gain and XIRR, mirroring NaviPlan's summary cards.
   - Tests: known XIRR examples, e.g. the Excel documentation example `-10000 @2008-01-01, 2750 @2008-03-01, 4250 @2008-10-30, 3250 @2009-02-15, 2750 @2009-04-01` → 37.34%. Also cover edge cases.
2. **Tax lots.** `Holding::TaxLots`, a PORO, replays trades FIFO per (account, security, folio_number). It yields **open lots** (buy date, qty, cost/unit) and **realized lots** (buy date, sell date, qty, cost, proceeds, holding days, gain), plus **per-redemption netting**: one row per sell trade with net gain, the way CAMS/KFintech capital-gains statements report it.
3. **Rules** in `config/india_capital_gains.yml`. This is **indicative**; encode it as data with effective dates and keep it easy to edit. Rules as of the Finance (No. 2) Act 2024, which the Income-tax Act 2025 carried into tax year 2026-27. **Verify before shipping.**
   - `equity` (listed shares, equity-oriented MF/ETF, ≥65% domestic equity): long-term if held >12 months.
     - Transfers before 2024-07-23: STCG 15%, LTCG 10%.
     - Transfers on or after 2024-07-23: STCG 20%, LTCG 12.5%.
     - LTCG exemption per person per FY: ₹1,00,000 up to FY 2023-24, ₹1,25,000 from FY 2024-25.
     - Grandfathering for lots bought on or before 2018-01-31: cost = max(actual cost, min(FMV on 2018-01-31, sale price)). FMV isn't available, so use actual cost and show a warning on those lots.
   - `debt` (specified MF, Sec 50AA: >65% debt / money-market): lots bought on or after 2023-04-01 are always taxed at the **slab** rate regardless of holding period. Older lots fall back to `other_unlisted`.
   - `other_unlisted` (hybrid 35–65% equity, gold/international FoF, pre-Apr-2023 debt MF):
     - Transfers before 2024-07-23: LT if >36 months, 20% with indexation. Indexation isn't computed, so show a note.
     - Transfers on or after 2024-07-23: LT if >24 months, 12.5% with no indexation.
     - STCG at the slab rate.
   - `other_listed` (gold ETF, other non-equity ETFs, listed bonds, SGB sold on exchange): from 2024-07-23, LT if >12 months, 12.5%. STCG at the slab rate.
   - `exempt`: SGB redeemed with RBI at maturity.
   - Not computed (shown as notes): surcharge, 4% cess, the 87A rebate interaction, and set-off/carry-forward rules beyond netting within the FY. Loss set-off ordering: STCL against STCG or LTCG; LTCL only against LTCG.
4. **Tax Center** (`/tax_center`, nav item "Tax", icon `receipt-indian-rupee` or the nearest available icon). Each section is a Turbo frame:
   1. **Realized gains this FY**, with FY selectable through the Phase 1 helpers. Totals by STCG-equity, LTCG-equity, slab-taxed, and LTCG-other. Show exemption used and remaining, and estimated base tax from a **slab rate input** (default 30%, kept in query params). Show the per-redemption netted table.
   2. **Harvesting.** Multi-select the accounts that belong to one person, because the exemption is per individual.
      - *LTCG harvesting*: for each folio, find the FIFO prefix of open lots that is long-term with a gain. Greedily choose units, fractional to 3 decimals, so total LTCG comes as close as possible to the remaining exemption **without exceeding it**. Output folio, scheme, units to sell, estimated proceeds and LTCG.
      - *Loss harvesting*: list lots with unrealized losses, labelled STCL/LTCL, that can offset realized gains.
      - FIFO is binding: units can only come from the front of the queue, and the recommendations must respect that.
   3. **Tax calculator.** Pick a holding, units, sale date (default today) and price (default the latest price). Output the FIFO lots consumed, the gain type per lot and the estimated tax. Inputs: slab rate, STCG/LTCG already realized this FY, and the optional "override holding period: only consider units held > N months" (this is a planning view; label it as not how the AMC will process the sale). Include a "View FIFO details" disclosure, using `<details>`.
   4. **Category mapping.** List the family's held securities with their effective tax category and asset class. Edits write `family_security_overrides`.
   5. **Export** to CSV (`send_data`) for the realized-gains table and the harvesting recommendations.
   - A persistent **disclaimer** across the page: "Indicative estimates only. Surcharge, cess and rebates are not computed. Consult a tax professional."

**Acceptance criteria**
- The XIRR tests pass.
- FIFO tests cover partial sells across lots, multiple folios of the same scheme, and switch-out as a sell.
- Classification tests check each category on both sides of 2023-04-01 and 2024-07-23, plus the 12/24/36-month thresholds.
- In the harvesting test, the recommended LTCG is ≤ the remaining exemption and within ₹1 of it when that's achievable.
- Controller tests render every Tax Center section.

---

### Phase 7: Goal planning (projections, glide path, rebalancing, emergency fund)

**Depends on:** Phase 2 (asset_class) and Phase 3 (FixedDeposit/ProvidentFund count as debt). **Runs:** in parallel with Phases 5 and 6.

1. **Schema** (`2026111707xxxx`).
   - `goals`: family_id, name, kind (retirement/education/home/vehicle/wedding/travel/emergency_fund/custom), target_amount (in today's money) + currency, target_date, inflation_rate (default 6.0), expected_equity_return (12.0), expected_debt_return (7.0), monthly_sip, sip_step_up_pct (default 10.0), initial_equity_pct (e.g. 70), final_equity_pct (e.g. 30), glide_path_years (e.g. 5), and notes.
   - Retirement fields: current_age, retirement_age, life_expectancy, monthly_expenses_today, post_retirement_return.
   - `goal_allocations`: goal_id, account_id, optional security_id, percentage (0–100). Validate that, across all goals, the allocations of the same (account, security) sum to ≤100.
2. **Domain POROs** in `app/models/goal/`.
   - `Goal::GlidePath#equity_pct_for(date)`: holds `initial_equity_pct` until `target_date - glide_path_years`, then de-risks linearly to `final_equity_pct` at `target_date`.
   - `Goal::Projection`:
     - Inflation-adjusted target = `target_amount·(1+inflation)^years`.
     - **Retirement corpus** = present value at retirement of inflation-growing annual expenses over `life_expectancy - retirement_age` years at `post_retirement_return` (growing annuity).
     - Current allocated value = Σ account or holding value × percentage.
     - Projected corpus: monthly simulation with a blended return from the glide path, plus the SIP stream with an annual step-up.
     - Shortfall or surplus.
     - **Required monthly SIP**, solved by bisection with the step-up.
     - Progress %.
   - `Goal::Rebalancer` compares the current allocated split (equity/debt/gold/other, from `Security#effective_asset_class`, with FixedDeposit, ProvidentFund and Depository counted as debt and PreciousMetal as gold) with the glide-path target for today. It suggests "Move ₹X from equity to debt", or the reverse, when the drift exceeds 5 percentage points.
   - **Emergency fund** goals: target = N months (default 6) × average monthly expenses over the last 6 months from `IncomeStatement`. Add a "Use my average expenses" button.
3. **UI.**
   - `/goals` index: cards with name, target (compact INR), date, a progress bar, an on-track/shortfall badge, and the required SIP.
   - `new` / `edit`: the form uses `<details>` for advanced assumptions.
   - `show`: projection chart (projected corpus versus inflation-adjusted target over time, with the existing D3 time-series controller or a small new one), glide-path table by year, allocations editor, and rebalancing suggestions.
   - "Plan first" works: a goal with no allocations still shows the required SIP.
   - Nav item "Goals" (icon `target`).

**Acceptance criteria**
- Projection math is unit-tested against hand-computed values: SIP future value with and without step-up, inflation, the retirement growing annuity, and required-SIP round-trips (simulating with the required SIP hits the target within 0.1%).
- Glide-path boundaries are tested.
- The allocation-sum validation is tested.
- Controller tests cover CRUD.

---

### Phase 8: Integration, assistant, demo data, docs, final QA

**Depends on:** all earlier phases. **Runs:** alone, last.

1. **AI assistant.** Add functions `GetGoals`, `GetTaxSummary` (FY realized gains and remaining exemption) and `GetHoldings` (with XIRR) in `app/models/assistant/function/`, following the existing function pattern, with tests.
2. **Demo data.** Update `app/models/demo/generator.rb` and `lib/tasks/demo_data.rake` for an Indian household:
   - HDFC savings with UPI/NEFT narrations, an ICICI credit card, and a Zerodha demat with RELIANCE, TCS, INFY and NIFTYBEES on XNSE.
   - MF holdings with folios: a flexi-cap, a large-cap index and a liquid fund (AMFI pseudo-MIC).
   - EPF, PPF, an FD, a home loan, a gold account, two insurance policies, and three goals (retirement, child education, emergency fund).
   - Indian merchants.
   - Offline securities are fine for demo prices; seed `security_prices`.
3. **Docs.** Write `docs/india.md` covering features, data sources and their reliability caveats, the tax disclaimer, and how to refresh NAVs offline. Add the new ENV vars to `.env.example` / `.env.local.example`: `PRODUCT_NAME` and `DISABLE_INDIAN_MARKET_DATA`. Update the README feature list.
4. **Consistency sweep.** Check nav order (Home, Transactions, Budgets, Goals, Tax, Funds). Mobile nav has at most 5 items. Check dark mode on every new page. Check for leftover "Maybe" strings, empty states on every new page, and N+1 queries on the new pages (use `includes`).
5. **Full CI.** Run `bin/rails test`, `bin/rubocop -f github -a`, `bundle exec erb_lint ./app/**/*.erb -a` and `bin/brakeman --no-pager`. Everything must be green except the 7 known Plaid errors. Fix brakeman warnings, or add justified entries to `config/brakeman.ignore`.
6. **System test.** One system test for the critical India flow: import a synthetic CAS text with PDF extraction stubbed, see holdings and XIRR, then open the Tax Center. Use the pre-installed Chromium.

---

## 4. Execution plan (orchestration)

| Wave | Phases (parallel within a wave) | Isolation | Notes |
|---|---|---|---|
| 1 | Phase 1 | main checkout, branch `claude/peaceful-darwin-s89wtn` | Foundation that everyone builds on |
| 2 | Phase 2 · Phase 3 · Phase 4 | one git worktree each | Orchestrator merges into the branch, fixes `schema.rb`/`routes.rb`/nav conflicts, and runs the full suite |
| 3 | Phase 5 · Phase 6 · Phase 7 | one git worktree each | Same merge procedure |
| 4 | Phase 8 | main checkout | Final QA, then push |

**Merge conflicts to expect:**
- `db/schema.rb`: union the tables and take the max version.
- `config/routes.rb` and the nav items array in `app/views/layouts/application.html.erb`: union both sides.
- `Accountable::TYPES`.
- `config/schedule.yml`.

After each wave, the orchestrator reloads the schema into a fresh test DB, runs the full suite, and pushes to `origin/claude/peaceful-darwin-s89wtn`.

### 4.1 Sub-agent report format

Every phase agent ends with:
1. Commits made (`git log --oneline` for the phase).
2. Migrations added, and confirmation that `db/schema.rb` was hand-edited and loads.
3. Test results: full-suite totals, plus the new test files and their counts.
4. Deviations from this plan and why.
5. Known gaps and TODOs, especially anything left unverified: bank or broker formats, tax rules, interest rates.

---

## 5. Later (out of scope for this plan)

- Account Aggregator (RBI AA framework, e.g. Setu/Finvu/OneMoney) for automatic bank and MF sync. It needs a FIU licence or partner.
- NPS statement (KFintech/Protean CRA) parsing and NPS scheme NAVs.
- Demat MF holdings from the NSDL/CDSL CAS.
- Google Drive backups and PWA offline mode.
- Full ITR helper: old vs new regime slab calculator, 80C/80D tracking, advance-tax reminders.
- Hindi and other Indian-language UI (the project currently hardcodes English by policy).
- Crypto VDA tax (30% + 1% TDS) and F&O/intraday business-income treatment.

## 6. Risks

| Risk | Mitigation |
|---|---|
| Yahoo Finance is unofficial and may break or rate-limit | Isolated provider behind `SecurityConcept`; easy to swap for NSE bhavcopy or a paid feed |
| CAS layouts drift and PDF text extraction is fragile | Parser runs on text with tolerant regexes and many fixtures; clear "couldn't parse line N" errors |
| Tax rules change every Budget | Rules in effective-dated YAML, disclaimer on every screen, "verify each FY" comments |
| Interest rates (PPF/EPF/FD) change quarterly | Effective-dated YAML, overridable per account |
| Parallel worktrees conflict | Timestamp blocks per phase; orchestrator merges in a fixed order (2→3→4, 5→6→7) |
