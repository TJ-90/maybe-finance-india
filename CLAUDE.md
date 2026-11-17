# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About this fork

- This is the **India edition** of Maybe Finance: a personal finance app for Indian households (INR, lakh/crore, April-March financial year, mutual funds, Tax Center, goals). Licensed AGPLv3, same as upstream.
- It is **not affiliated with or endorsed by Maybe Finance Inc.** "Maybe" is their trademark.
- **Never use the "Maybe" name or logo in user-facing text** (views, emails, the assistant prompt, page titles). Use the `product_name` helper (`app/helpers/application_helper.rb`) or `Rails.configuration.x.product_name` (set in `config/application.rb` from ENV `PRODUCT_NAME`, placeholder default "Kosh"). Internal identifiers such as the `Maybe` Ruby module stay as they are, to keep the code mergeable with upstream.
- The feature-parity target is NaviPlan (a paid Indian planning product). Build from public data formats and public descriptions only. **Never copy its branding, copy or code**, and never use its name in the product.
- Read `docs/india.md` for what is verified and what is not, `README.md` for the fork notice, and `plan.md` for the history (phases 1-11, round 2 in section 8, status in section 7). `plan.md` is a log: where it disagrees with the code, the code wins.

## Common Development Commands

### Development Server
- `bin/dev` - Start development server (Rails, Sidekiq, Tailwind CSS watcher)
- `bin/rails server` - Start Rails server only (agents must not run it, see Development Guidelines)
- `bin/rails console` - Open Rails console

### Testing
- `bin/rails test` - Run all tests
- `bin/rails test:db` - Run tests with database reset
- `bin/rails test:system` - Run system tests only (use sparingly - they take longer)
- `bin/rails test test/models/account_test.rb` - Run specific test file
- `bin/rails test test/models/account_test.rb:42` - Run specific test at line

### Linting & Formatting
- `bin/rubocop -f github -a app test config db/migrate lib` - Ruby linter with auto-correct. **Always pass these paths.** With no paths it reformats `db/schema.rb`, which must not be committed.
- `bundle exec erb_lint ./app/**/*.erb -a` - ERB linter
- `npm run lint` - Check JavaScript/TypeScript code
- `npm run lint:fix` - Fix JavaScript/TypeScript issues
- `npm run format` - Format JavaScript/TypeScript code
- `bundle exec brakeman --no-pager -q --no-exit-on-warn` - Security analysis. `bin/brakeman` fails here because it adds `--ensure-latest`.

### Database
- `bin/rails db:prepare` - Create and migrate database
- `bin/rails db:migrate` - Run pending migrations (the owner runs this, agents do not, see Migrations)
- `bin/rails db:rollback` - Rollback last migration
- `bin/rails db:seed` - Load seed data
- `RAILS_ENV=test bin/rails db:schema:load` - Load `db/schema.rb` into the test database (first time, and after every `schema.rb` edit)

### Setup
- `bin/setup` - Initial project setup (installs dependencies, prepares database)
- `bin/rails demo_data:default` - Build the Indian demo household (see Demo data)

## Pre-Pull Request CI Workflow

ALWAYS run these commands before opening a pull request:

1. **Tests** (Required):
   - `bin/rails test` - Run all tests (always required)
   - `bin/rails test:system` - Run system tests (only when applicable, they take longer)

2. **Linting** (Required):
   - `bin/rubocop -f github -a app test config db/migrate lib` - Ruby linting with auto-correct
   - `bundle exec erb_lint ./app/**/*.erb -a` - ERB linting with auto-correct

3. **Security** (Required):
   - `bundle exec brakeman --no-pager -q --no-exit-on-warn` - Security analysis

Only proceed with pull request creation if ALL checks pass. Known baseline, which does not block:
- **Tests:** 7 errors come from missing Plaid credentials: `test/models/provider/plaid_test.rb` (6) and `UsersControllerTest#test_admin_can_reset_family_data` (1). Everything else must pass.
- **Brakeman:** one warning remains, Rails 7.2 end of life.

## General Development Rules

### Authentication Context
- Use `Current.user` for the current user. Do NOT use `current_user`.
- Use `Current.family` for the current family. Do NOT use `current_family`.

### Development Guidelines
- Prior to generating any code, carefully read the project conventions and guidelines
- Ignore i18n methods and files. Hardcode strings in English for now to optimize speed of development
- Do not run `rails server` in your responses
- Do not run `touch tmp/restart.txt`
- Do not run `rails credentials`
- Do not automatically run migrations
- Do not touch the development database or run `demo_data` tasks unless the person asked for it (someone may be using that database and server at the same time). Tests use their own test database.

## High-Level Architecture

### Application Modes
The app runs in two distinct modes:
- **Managed**: The operator runs the servers for users (Rails.application.config.app_mode = "managed")
- **Self Hosted**: Users host the app on their own infrastructure, typically through Docker Compose (Rails.application.config.app_mode = "self_hosted"). This fork is aimed at self-hosting.
- Set `SELF_HOSTED=true` locally to avoid the subscription paywall.

### Core Domain Model
The application is built around financial data management with these key relationships:
- **Family** → has many **HouseholdMembers**, **Users**, **Accounts**, **Goals**, **InsurancePolicies**
- **User** → belongs to a family (optionally linked to a **HouseholdMember**)
- **Account** → has many **Entries** (**Transaction**, **Trade**, **Valuation** entryables)
- **Account** types (accountables, `app/models/concerns/accountable.rb`): Depository, Investment, FixedDeposit, ProvidentFund, Crypto, PreciousMetal, Property, Vehicle, OtherAsset, CreditCard, Loan, OtherLiability
- **Transaction** → belongs to **Category**, can have **Tags** and **Rules**
- **Investment accounts** → have **Holdings** → track **Securities** via **Trades**

### API Architecture
The application provides both internal and external APIs:
- Internal API: Controllers serve JSON via Turbo for SPA-like interactions
- External API: `/api/v1/` namespace with Doorkeeper OAuth and API key authentication
- API responses use Jbuilder templates for JSON rendering
- Rate limiting via Rack Attack with configurable limits per API key

### Sync & Import System
Data ingestion methods:
1. **CSV / PDF / Excel import** (the main path for Indian users): `Import` manages import sessions. See "Imports" below.
2. **Manual entry**: transactions, trades, valuations, and the Indian instruments.
3. **Plaid integration** (inherited from upstream, US/EU banks only, not useful for India): `PlaidItem`, `Sync`, background jobs. Plaid has no test credentials here, hence the baseline errors above.

### Background Processing
Sidekiq handles asynchronous tasks:
- Account syncing (`SyncJob`), import processing (`ImportJob`), AI chat responses (`AssistantResponseJob`)
- Market data, re-valuation, goal monitoring and reminders (see "Market data")
- Scheduled work lives in `config/schedule.yml` (sidekiq-cron). Cron is UTC, so each entry carries an IST comment.

### Frontend Architecture
- **Hotwire Stack**: Turbo + Stimulus for reactive UI without heavy JavaScript
- **ViewComponents**: Reusable UI components in `app/components/`
- **Stimulus Controllers**: Handle interactivity, organized alongside components
- **Charts**: D3.js for financial visualizations (time series, donut, sankey)
- **Styling**: Tailwind CSS v4.x with custom design system
  - Design system defined in `app/assets/tailwind/maybe-design-system.css`
  - Always use functional tokens (e.g., `text-primary` not `text-white`)
  - Prefer semantic HTML elements over JS components
  - Use `icon` helper for icons, never `lucide_icon` directly

### Multi-Currency Support
- Default currency is INR (`Money.default_currency`). New families default to INR / IN / `%d-%m-%Y` / `Asia/Kolkata` (`Family#india?`).
- All monetary values are stored in the account's currency and converted to the family's base currency for totals.
- Exchange rates come from Frankfurter (ECB data, keyless) first, then Synth if configured.
- `Money` objects handle currency conversion and formatting. Historical exchange rates are used for accurate reporting.
- **Always format on the server**, with `format_money` / `format_money_compact` (`app/helpers/application_helper.rb`; implementation in `lib/money/formatting.rb`). INR uses lakh/crore grouping (`₹12,34,567`); the compact form gives `₹45.6K`, `₹12.35 L`, `₹1.20 Cr`. Do not format money in JS (chart tick labels excepted).

### Security & Authentication
- Session-based auth for web users
- API authentication via:
  - OAuth2 (Doorkeeper) for third-party apps
  - API keys with JWT tokens for direct API access
- Scoped permissions system for API access
- Strong parameters and CSRF protection throughout

### Testing Philosophy
- Comprehensive test coverage using Rails' built-in Minitest
- Fixtures for test data (avoid FactoryBot)
- Keep fixtures minimal (2-3 per model for base cases)
- VCR for external API testing of upstream providers; **Indian providers use webmock stubs and fixture payloads instead** (see "No live network in tests")
- System tests for critical user flows (use sparingly)
- Test helpers in `test/support/` for common scenarios
- Only test critical code paths that significantly increase confidence
- Write tests as you go, when required

### Performance Considerations
- Database queries optimized with proper indexes
- N+1 queries prevented via includes/joins
- Background jobs for heavy operations
- Caching strategies for expensive calculations
- Turbo Frames for partial page updates

### Development Workflow
- Feature branches merged to `main`
- Docker support for consistent environments
- Environment variables via `.env` files (`.env.example` for self-hosting, `.env.local.example` for development)
- Lookbook for component development (`/lookbook`)
- Letter Opener for email preview in development

## India Domain Architecture

### Financial year and formatting
- The financial year runs April to March. Use `Period.current_financial_year`, `Period.last_financial_year`, `Period.financial_year_for(date)`, and the class methods `financial_year_start`, `financial_year_range`, `financial_year_label` in `app/models/period.rb`. Do not hand-roll FY maths.
- Dates display as `dd-mm-yyyy`. Money formatting: see Multi-Currency Support above.
- Test fixtures in `test/fixtures/families.yml` are pinned to USD/US, so pass currencies explicitly in tests.

### Market data
- **Providers** (`app/models/provider/`), looked up through `Provider::Registry` (`registry.rb`):
  - `Amfi`: reads AMFI `NAVAll.txt` (scheme list plus latest NAV).
  - `Mfapi`: NAV history for one scheme (`api.mfapi.in`).
  - `YahooFinance`: NSE (`.NS`) and BSE (`.BO`) prices and search. Unofficial endpoints.
  - `IndianMarkets`: the facade for securities. It **routes by MIC** (`exchange_operating_mic`): `Security::AMFI_MIC` (`"AMFI"`, a pseudo-MIC for mutual funds, where **ticker = AMFI scheme code**) goes to `Mfapi`; `Security::NSE_MIC` (`XNSE`) and `Security::BSE_MIC` (`XBOM`) go to `YahooFinance`; anything else goes to the Synth fallback.
  - `Frankfurter`: exchange rates.
  - `Synth`: optional paid fallback for markets outside India (`SYNTH_API_KEY`).
  - Registry order: `:exchange_rates` is `frankfurter`, then `synth`. `:securities` is `indian_markets`, then `synth`. `Registry.amfi`, `.frankfurter` and `.indian_markets` return nil when `DISABLE_INDIAN_MARKET_DATA=true`.
- **AMFI NAVAll format** (`Provider::Amfi`, header comment documents both): the current 8-column layout `Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Plan;Option;Net Asset Value;Date`, and the legacy 6-column layout without Plan/Option. The layout is detected from the header line. In the current layout the stored name is rebuilt as `<name> - <Plan> - <Option>`. Category lines and AMC lines (no semicolons) group the scheme rows. An import of zero schemes overwrites nothing. Fixtures: `test/fixtures/files/navall_current_format.txt`, `navall_sample.txt`.
- **Scheduled jobs** (`config/schedule.yml`, switches in `app/models/market_data.rb`):
  - `ImportMutualFundSchemesJob`, 23:30 IST nightly: AMFI schemes and latest NAVs (`MutualFundScheme.import_navall!`).
  - `ImportMarketDataJob`, 00:00 IST nightly (FX and catch-up) and 16:15 IST on weekdays (`scope: exchange_close`, NSE/BSE closes).
  - `RefreshIntradayPricesJob`, every 15 minutes on weekdays, works only 09:15-15:30 IST (`Security::IntradayRefresh`).
  - `SecurityHealthCheckJob`, `SyncCleanerJob`: inherited.
  - **Re-valuation chain:** after each price import, `RefreshInvestmentValuesJob` re-syncs the accounts that hold a security whose price changed (and accounts in a currency whose rate changed), via `Account::Revaluation`. Without it, holdings, net worth and XIRR only refresh when a family syncs. `MarketData.refresh_now` is the "Refresh prices now" action.
  - Then goal monitoring (01:00 IST) and reminders (01:30 IST), see Goals.
- **Dev behaviour:** scheduled market jobs are skipped in development unless `ENABLE_MARKET_DATA_IN_DEV=true` (`MarketData.jobs_enabled?`). Manual refreshes still run.
- **Settings → Market data** (`app/controllers/settings/market_data_controller.rb`) shows active sources, refreshes prices and uploads `NAVAll.txt` for offline use.
- Mutual fund pages and discovery: `MutualFundScheme.search` / `.discover`, `app/controllers/mutual_funds_controller.rb`. Trailing 1Y/3Y/5Y CAGR: `Security::TrailingReturns`.

### Securities and classification
- `Security` (`app/models/security.rb`) has `kind` (`KINDS`: stock, etf, mutual_fund, bond, gold, other), `asset_class` (`ASSET_CLASSES`: equity, debt, hybrid, gold, international, other), `tax_category` (`TAX_CATEGORIES`: equity, debt, other_listed, other_unlisted, exempt), and `isin`. The enums use prefixes: `kind_mutual_fund?`, `asset_class_equity?`, `tax_category_debt?`.
- Funds are classified from AMFI category names in `MutualFundScheme` (`infer_asset_class`, `infer_tax_category`). A wrong guess changes tax treatment.
- **Always read classification through `security.effective_tax_category(family)` / `effective_asset_class(family)`**, which honour `FamilySecurityOverride` (per-family override, unique per family and security). Never read the raw column in tax code. Overrides are edited in the Tax Center Categories tab (`TaxCenter::CategoryMapping`).
- `Security#display_name` is the name to show. Trades are named after it: `Trade.build_name` gives "Buy 3.368 units of <Fund name>" for funds and "shares" for stocks. Every importer and the trade form call it.
- A fund that AMFI does not know yet (from a CAS import) is kept as an offline security named after its ISIN, and relinked to its scheme code by a later NAV import (`MutualFundScheme.relink_offline_securities!`).
- `trades.folio_number` identifies a folio. Lots are grouped per folio.

### Returns
- `Xirr` (`app/models/xirr.rb`): Newton with bisection fallback; nil when it cannot be computed.
- `Holding::Returns` (invested, gain, absolute %, XIRR, 1-day change, CAGR since first purchase, "--" under one year), `Account::Returns` (account and portfolio level, `prices_last_updated_at`), `InvestmentSummary`. These are model methods: do not compute returns in views.
- `Holding::TaxLots`: FIFO lots per folio and per account. It is shared by returns and the Tax Center.

### Indian instruments and generated entries
- Accountables: `FixedDeposit` (fd, rd, nsc, kvp, scss, pomis, corporate_fd; `FixedDeposit::Accruer`), `ProvidentFund` (epf, vpf, ppf, ssy; `ProvidentFund::InterestCalculator`, `::InterestPoster`), `PreciousMetal` (gold and silver by weight and purity). Bank accounts get NRE/NRO subtypes.
- `InsurancePolicy` is **not an account** and never part of net worth. Policy numbers are encrypted at rest.
- `BalanceSheet::IndiaBreakdown` (`balance_sheet.india_breakdown`) powers the net worth card (market assets, retirement funds, cash, property and vehicles, other).
- **Generated entries** (`app/models/account/generated_entries.rb`): entries the system derives (FD value accruals, interest credits, payouts) carry `entries.generated_by` and `generated_user_edited`. `Account::Syncer` calls `generate_auto_entries!`, which calls `replace_generated_entries!(source, specs)` on the accountable's behalf. Only generated, unedited entries are deleted and recreated. Once a user edits one it becomes theirs. A generated valuation never lands on a date that already has a valuation. Keep it idempotent.
- Interest rates come from `config/india_small_savings_rates.yml` via `SmallSavingsRates`. A rate set on an account always wins.

### Household members and ownership
- `HouseholdMember` (`app/models/household_member.rb`): name, relationship (self/spouse/parent/child/other), **`residency_status` (`resident` or `nri`) which is required and has no default**: every form must present the choice explicitly, never pre-select it. Also optional date of birth, `pan_last4`, `slab_rate` (defaults to 30 for NRI), `tax_regime`.
- Ownership: `accounts.household_member_id` (nil means "Joint / household", `Account::Ownership`, which also gives `residency_warnings` such as no new PPF for an NRI), `goals.household_member_id`, and optionally `users.household_member_id`.
- The dashboard filters with `?member=`. The Tax Center works one member at a time. Imports ask "Whose account is this?" when they create an account. Managed in Settings → Household (`app/controllers/settings/household_members_controller.rb`).

### Tax Center
- `app/models/tax_center/` and `app/controllers/tax_center_controller.rb`. Pieces: `Rules` (reads the YAML), `Calculation`, `Report` (redemption-wise gains like a CAMS/KFintech statement), `GainLine`, `Estimate` (set-off and indicative tax), `Harvester` (LTCG and loss harvesting up to the exemption), `SaleSimulator`, `Residency`, `InterestIncome`, `CategoryMapping`, `Export` (CSV).
- Lots are **FIFO per folio** (`Holding::TaxLots`).
- Rules are **effective-dated** in `config/india_capital_gains.yml`: holding periods, LTCG/STCG rates by transfer date, the Sec 112A exemption (₹1.25 L from FY 2024-25), Sec 50AA specified-MF rules, grandfathering cutoff, and a `residency:` section (NRI TDS rates and notes, resident notes, interest TDS thresholds).
- Same for Resident and NRI: capital-gains rates and the 112A exemption. NRI gets an estimated TDS on each sale (4% cess added, surcharge and DTAA not modelled) and an interest section (NRE exempt, NRO taxable). Residents get notes only.
- **Everything here is indicative, not tax advice.** Not modelled: surcharge, cess on tax, the 87A rebate, loss carry-forward, indexation, and pre-2018 grandfathered values (actual cost is used with a warning). Keep that disclaimer wherever numbers are shown. The assistant function `GetTaxSummary` repeats it.

### Goals, snapshots and notifications
- `Goal` (`app/models/goal.rb`): kinds retirement, education, home, vehicle, wedding, travel, emergency_fund, custom. Collaborators: `Goal::Projection` (inflation-adjusted corpus, SIP with step-up), `Goal::GlidePath`, `Goal::Rebalancer`, `Goal::Health` (dashboard card). `GoalAllocation` links holdings to goals by percentage. Retirement goals use the member's date of birth.
- `GoalSnapshot`: one row per goal per day (unique on goal and date), status `on_track` / `at_risk` / `off_track`. Written by `MonitorGoalsJob` (01:00 IST) through `Goal#record_snapshot!`. Idempotent.
- `Notification` (`app/models/notification.rb`) with per-user `NotificationPreference`. `Notification.notify` takes a `dedupe_key` so a reminder is raised once per window. Producers: `Notification::GoalAlerts` (status changes, monthly summary) and `Notification::Reminders` (stale investment data, stale NAVs, insurance premium due, March tax review), run by `SendRemindersJob` (01:30 IST). `SendNotificationDigestsJob` (09:00 IST) emails the digest.
- **Email is sent only when `SMTP_ADDRESS` is set and the user opted in** (`Notification.email_delivery_configured?`). Emails contain **no amounts** unless the user turns that on.

### Imports
All in `app/models/`. `Import::TYPES` lists them.
- **Bank and card CSV:** `TransactionImport` with `Import::StatementPreset` over `config/india_statement_presets.yml` (HDFC, ICICI, SBI, Axis, Kotak, IDFC FIRST, Yes, cards, generic). Debit and credit columns use the `debit_credit_columns` amount strategy, and `Import.strip_preamble` drops account details above the header. `Transaction::NarrationParser` extracts payment mode (`transactions.payment_mode`), counterparty and `reference_number` from UPI/NEFT/IMPS/RTGS/NACH/ATM/card/cheque narrations. `Transaction::MerchantHint` suggests categories from `config/india_merchant_categories.yml`, only for rows with no category.
- **CAS PDF:** `CasImport` with `CasImport::Parser` and `CasImport::PdfText` (uses `pdf-reader`, `qpdf` as a fallback for some encryption). Detailed and summary statements, password-protected files. The PDF and its password are read in memory and **never persisted**. Investors are mapped to household members on a mapping step. A summary CAS creates one opening position per scheme at cost, so XIRR and lots are approximate.
- **Broker tradebooks:** `BrokerTradebookImport` (a `TradeImport`) with `Import::BrokerPreset` over `config/india_broker_presets.yml`: `zerodha_console`, `mf_template` (defined by this app), `groww_mf_orders` (Groww mutual fund order history), `generic_broker` (best-effort). Preset-driven rows need no column mapping.
- **Fund-name matching** (for exports with no ISIN or scheme code, such as Groww): `MutualFundScheme::NameMatcher` accepts only a single clear winner and never guesses; the rest goes to the "Match your funds" step (`Import::SchemeMapping`). It needs the AMFI list loaded.
- **Excel:** every CSV-based import also accepts `.xlsx`. `Import::XlsxReader` converts the first sheet to CSV with no extra gem (size caps, no DTDs or external entities). Numeric date cells become `YYYY-MM-DD`. Binary `.xls` is not supported.
- Imports are idempotent: re-importing does not duplicate trades.
- Statement layouts are mostly unverified against real exports. Labels in the UI and `docs/india.md` say which. When you add a preset, only mark it confirmed if a real export was checked.

### Assistant
`app/models/assistant/function/` exposes accounts, holdings (with XIRR), goals and tax summary. The assistant is told not to give tax or investment advice.

## Conventions learned while building the India edition

### Financial and tax rules live in effective-dated YAML
Never put a rate, threshold, limit or date-dependent rule inline in code. Put it in `config/` with an effective date and a `Verify each financial year` comment at the top, and read it through a model. Files:
- `config/india_capital_gains.yml`: capital-gains rules, 112A exemption, 50AA, residency and TDS (`TaxCenter::Rules`)
- `config/india_small_savings_rates.yml`: EPF, PPF, SSY, NSC, KVP, SCSS, POMIS (`SmallSavingsRates`)
- `config/india_statement_presets.yml`: bank and card CSV layouts (`Import::StatementPreset`)
- `config/india_broker_presets.yml`: broker and MF layouts (`Import::BrokerPreset`)
- `config/india_merchant_categories.yml`: merchant to category hints (`Transaction::MerchantHint`)
- `config/schedule.yml`: cron entries for the jobs

When a rule changes, add a dated entry. Do not overwrite history, because past financial years are still computed with old rules.

### Migrations
- `CLAUDE.md` says do not automatically run migrations, so: **write the migration, then hand-edit `db/schema.rb` to match it exactly** (tables alphabetical, indexes, `add_foreign_key` lines at the bottom, `define(version: ...)` set to the highest migration timestamp). **Never run `db:migrate`.**
- Load the hand-edited schema into the test database with `RAILS_ENV=test bin/rails db:schema:load`. A schema that fails to load means the `schema.rb` edit is wrong.
- **Rails 7.2 rejects migration timestamps more than a day in the future.** Use real current-date timestamps (`YYYYMMDDHHMMSS`), not invented later blocks. Keep them above the newest existing migration.
- Lint with `bin/rubocop -f github -a app test config db/migrate lib`, never with no paths (it reformats `schema.rb`).
- Data fixes go in rake tasks under `lib/tasks/data_migration.rake` (for example `rename_auto_named_trades`), with tests.
- The owner must run `bin/rails db:migrate` after pulling. Say so in your report when you add a migration.

### No live network in tests
- `test/test_helper.rb` sets `DISABLE_INDIAN_MARKET_DATA=true` and loads `webmock/minitest`, so tests can never reach AMFI, MFAPI, Yahoo or Frankfurter.
- Provider tests stub HTTP with fixture payloads under `test/fixtures/files/` (`navall_*.txt`, `mfapi_scheme_100001.json`, `yahoo_chart_reliance.json`, `yahoo_search_sample.json`, `frankfurter_range_usd_inr.json`). Do not record VCR cassettes for Indian sources.
- To exercise a provider in a test, re-enable it: `with_env_overrides DISABLE_INDIAN_MARKET_DATA: nil do ... end` (`with_env_overrides` is defined in `test_helper.rb`).
- Indian data sources have not been exercised against their live services. Treat the first live run as a test and say so when you change a parser.

### Privacy
- **Never commit real statements or personal data**: names, PAN, mobile numbers, real transactions or amounts, or the user's real fund names. This includes fixtures, tests, docs and commit messages.
- Fixtures must be synthetic (fake names, PAN `ABCDE1234F`, made-up folios). See `test/fixtures/files/cas/` and `test/fixtures/files/imports/`.
- CAS PDFs and their passwords are never persisted or logged.
- Notification emails contain no amounts by default.
- The only outbound requests are market data lookups, which send scheme codes, tickers and currency pairs, never amounts or names.

### Testing environment notes
- The Ruby version in `.ruby-version` may not be installable in a sandbox. If so, use a nearby Ruby with an unpinned copy of the Gemfile through `BUNDLE_GEMFILE`, and never commit changes to the `ruby` line of the repo `Gemfile` or the `RUBY VERSION` in `Gemfile.lock`. Use a separate test database per parallel worker (`POSTGRES_DB`).
- **System tests:** run with `CI=1` so Chrome is headless (`test/application_system_test_case.rb`). If the chromedriver and Chrome major versions differ, a wrapper that starts chromedriver with `--disable-build-check` works. Say in your report if you could not run them.
- Adding a gem needs a written justification. Only `pdf-reader` was added for this fork. When adding one in a sandbox, copy only its lines into the repo `Gemfile.lock`.

### Demo data
- `bin/rails demo_data:default` (`lib/tasks/demo_data.rake`, `app/models/demo/generator.rb`) builds an Indian household. **Rahul is the NRI** (`user@example.com` / `password`), **Asha is Resident** (`partner_user@example.com`). It has NRE and NRO accounts, a demat, mutual funds with folios, EPF, PPF, an FD, gold, a joint home loan, insurance, goals and sample notifications.
- It is network-free: it uses made-up fund schemes (codes `900001` to `900003`) and seeds a price for every day. Keep it that way, and keep the generator test passing.
- It writes to the development database. Do not run it unless asked.

### Environment variables
| Variable | Purpose |
|---|---|
| `PRODUCT_NAME` | Product name in the UI, emails and assistant. Default placeholder "Kosh". |
| `DISABLE_INDIAN_MARKET_DATA` | `true` turns off AMFI, MFAPI, Yahoo and Frankfurter. Tests set it. |
| `INTRADAY_PRICE_REFRESH` | Defaults to on. `false` turns off the 15-minute NSE/BSE refresh. |
| `ENABLE_MARKET_DATA_IN_DEV` | `true` lets scheduled market jobs run in development. |
| `GITHUB_REPO` | `owner/repo` for changelog and feedback links. Empty hides both. |
| `SMTP_ADDRESS` | Gates notification email (with `SMTP_*` and `EMAIL_SENDER`). |
| `SYNTH_API_KEY` | Optional fallback for non-Indian prices and rates. |
| `SELF_HOSTED` | `true` for self-hosted mode (no paywall). |

Document any new variable in `.env.example` and here.

## Project Conventions

### Convention 1: Minimize Dependencies
- Push Rails to its limits before adding new dependencies
- Strong technical/business reason required for new dependencies
- Favor old and reliable over new and flashy
- Example: `.xlsx` reading is a small zip and XML reader (`Import::XlsxReader`), not a spreadsheet gem.

### Convention 2: Skinny Controllers, Fat Models
- Business logic in `app/models/` folder, avoid `app/services/`
- Use Rails concerns and POROs for organization
- Models should answer questions about themselves: `account.balance_series` not `AccountSeries.new(account).call`
- Indian logic follows this too: `account.xirr`, `security.effective_tax_category(family)`, `goal.projection`, not controller or view code.

### Convention 3: Hotwire-First Frontend
- **Native HTML preferred over JS components**
  - Use `<dialog>` for modals, `<details><summary>` for disclosures
- **Leverage Turbo frames** for page sections over client-side solutions
- **Query params for state** over localStorage/sessions (`?member=` is an example)
- **Server-side formatting** for currencies, numbers, dates
- **Always use `icon` helper** in `application_helper.rb`, NEVER `lucide_icon` directly

### Convention 4: Optimize for Simplicity
- Prioritize good OOP domain design over performance
- Focus performance only on critical/global areas (avoid N+1 queries, mindful of global layouts)

### Convention 5: Database vs ActiveRecord Validations
- Simple validations (null checks, unique indexes) in DB
- ActiveRecord validations for convenience in forms (prefer client-side when possible)
- Complex validations and business logic in ActiveRecord

## TailwindCSS Design System

### Design System Rules
- **Always reference `app/assets/tailwind/maybe-design-system.css`** for primitives and tokens (the file name is internal, keep it)
- **Use functional tokens** defined in design system:
  - `text-primary` instead of `text-white`
  - `bg-container` instead of `bg-white`
  - `border border-primary` instead of `border border-gray-200`
- **NEVER create new styles** in design system files without permission
- **Always generate semantic HTML**

## Component Architecture

### ViewComponent vs Partials Decision Making

**Use ViewComponents when:**
- Element has complex logic or styling patterns
- Element will be reused across multiple views/contexts
- Element needs structured styling with variants/sizes
- Element requires interactive behavior or Stimulus controllers
- Element has configurable slots or complex APIs
- Element needs accessibility features or ARIA support

**Use Partials when:**
- Element is primarily static HTML with minimal logic
- Element is used in only one or few specific contexts
- Element is simple template content
- Element doesn't need variants, sizes, or complex configuration
- Element is more about content organization than reusable functionality

**Component Guidelines:**
- Prefer components over partials when available (design-system components are in `app/components/DS`)
- Keep domain logic OUT of view templates
- Logic belongs in component files, not template files

### Stimulus Controller Guidelines

**Declarative Actions (Required):**
```erb
<!-- GOOD: Declarative - HTML declares what happens -->
<div data-controller="toggle">
  <button data-action="click->toggle#toggle" data-toggle-target="button">Show</button>
  <div data-toggle-target="content" class="hidden">Hello World!</div>
</div>
```

**Controller Best Practices:**
- Keep controllers lightweight and simple (< 7 targets)
- Use private methods and expose clear public API
- Single responsibility or highly related responsibilities
- Component controllers stay in component directory, global controllers in `app/javascript/controllers/`
- Pass data via `data-*-value` attributes, not inline JavaScript

## Testing Philosophy

### General Testing Rules
- **ALWAYS use Minitest + fixtures** (NEVER RSpec or factories)
- Keep fixtures minimal (2-3 per model for base cases)
- Create edge cases on-the-fly within test context
- Use Rails helpers for large fixture creation needs

### Test Quality Guidelines
- **Write minimal, effective tests** - system tests sparingly
- **Only test critical and important code paths**
- **Test boundaries correctly:**
  - Commands: test they were called with correct params
  - Queries: test output
  - Don't test implementation details of other classes

### Testing Examples

```ruby
# GOOD - Testing critical domain business logic
test "syncs balances" do
  Holding::Syncer.any_instance.expects(:sync_holdings).returns([]).once
  assert_difference "@account.balances.count", 2 do
    Balance::Syncer.new(@account, strategy: :forward).sync_balances
  end
end

# BAD - Testing ActiveRecord functionality
test "saves balance" do 
  balance_record = Balance.new(balance: 100, currency: "USD")
  assert balance_record.save
end
```

### Stubs and Mocks
- Use `mocha` gem
- Prefer `OpenStruct` for mock instances
- Only mock what's necessary
- For HTTP, use webmock stubs with fixture files (Indian providers) rather than mocking the provider class

## Glossary

- **AMFI**: Association of Mutual Funds in India. Publishes the public scheme and NAV list.
- **NAV / NAVAll.txt**: Net Asset Value per unit of a fund. `NAVAll.txt` is AMFI's daily file of every scheme's latest NAV.
- **CAS**: Consolidated Account Statement of all mutual fund holdings, issued by CAMS and KFintech (the two registrars). Detailed has every transaction, summary has holdings only.
- **Folio**: an investor's account number with one fund house (AMC). The same fund can sit in several folios.
- **SIP**: Systematic Investment Plan, a fixed periodic purchase (usually monthly), often with a yearly step-up.
- **XIRR**: annualised return for dated, irregular cash flows.
- **CAGR**: compound annual growth rate. Here it is price-based (since first purchase, or trailing 1Y/3Y/5Y from NAV history).
- **STCG / LTCG**: short- and long-term capital gains. The holding-period cut-off depends on the asset class and the sale date (12, 24 or 36 months); `config/india_capital_gains.yml` is the source of truth.
- **Sec 112A exemption**: the yearly amount of long-term equity gains that is tax-free per person (₹1.25 lakh from FY 2024-25, ₹1 lakh before).
- **Specified MF (Sec 50AA)**: debt-oriented mutual fund whose gains are taxed at the slab rate regardless of holding period.
- **TDS**: tax deducted at source, for example by the AMC or broker on an NRI's sale, or by a bank on interest.
- **NRE / NRO**: Non-Resident (External) and Non-Resident (Ordinary) rupee accounts. NRE interest is tax-exempt in India, NRO interest is taxable with TDS.
- **EPF / PPF / SSY / NPS**: Employees' Provident Fund, Public Provident Fund, Sukanya Samriddhi Yojana, National Pension System. VPF is the voluntary top-up of EPF.
- **IDCW**: Income Distribution cum Capital Withdrawal, the current name for a fund's dividend option (the alternative to Growth).
- **NRI / Resident**: residential status for tax. It decides TDS, set-offs and which accounts and instruments are allowed.
