# Kosh: personal finance for Indian households

> [!NOTE]
> "Kosh" is a placeholder product name. Set the `PRODUCT_NAME` environment variable to change the name shown in the app.

Kosh is a self-hostable personal finance app for Indian households. It tracks accounts, transactions, budgets, net worth and investments in rupees, with lakh/crore number formatting, the April to March financial year, Indian account types and Indian default categories. Everything runs on your own infrastructure, so your financial data stays with you.

## Features

Everything the upstream app does (accounts, transactions, budgets, rules, net worth history, multi-currency, an AI assistant) plus:

- **Indian foundation:** INR by default, lakh/crore formatting, the April to March financial year, Indian account types and default categories.
- **Statement import:** bank and credit card statement CSVs with presets, debit/credit columns, and UPI/NEFT/IMPS narration parsing (payment mode, merchant, reference number).
- **Investment import:** CAMS/KFintech CAS PDF (including password-protected files), the Zerodha Console tradebook (plus a best-effort generic broker layout) and a mutual fund CSV template.
- **Market data:** daily mutual fund NAVs from AMFI/MFAPI, NSE/BSE prices from Yahoo Finance, a fund discovery page, and an offline NAVAll.txt upload fallback.
- **Indian instruments:** FD/RD/NSC/KVP/SCSS, EPF/VPF/PPF/SSY with interest posting, gold and silver, and insurance policies (kept out of net worth), with a net worth card that separates market assets from retirement funds.
- **Returns:** XIRR per holding, per account and for the whole portfolio.
- **Tax Center:** FIFO lots, LTCG/STCG classification, redemption-wise gains like a CAS capital gains statement, tax-harvesting suggestions, a sale simulator and category overrides. Indicative only, not tax advice.
- **Goals:** target corpus with inflation, SIP with step-up, glide path, required SIP, rebalancing hints and an emergency fund goal.
- **AI assistant:** knows your holdings (with XIRR), goals and realized gains for the financial year.

Several data sources and statement formats are unverified against live services or real files. Read [docs/india.md](docs/india.md) for details and caveats. After pulling an update, run `bin/rails db:migrate` to apply the new tables.

## Fork notice

This project is a fork of [Maybe Finance](https://github.com/maybe-finance/maybe), an open source personal finance app that is no longer actively maintained. It is **not affiliated with or endorsed by** Maybe Finance Inc.

"Maybe" is a trademark of Maybe Finance Inc. This fork does not use the Maybe name or logo in the product. Internal code identifiers (such as the `Maybe` Ruby module) are kept only to keep the codebase mergeable and are not user-facing.

## License

Distributed under the [GNU AGPLv3 license](LICENSE), the same license as the upstream project. The original copyright notice is retained in `LICENSE`.

## Hosting

Kosh can be [self hosted with Docker](docs/hosting/docker.md).

## Local Development Setup

**If you are trying to _self-host_ the app, stop here. You
should [read this guide to get started](docs/hosting/docker.md).**

The instructions below are for developers to get started with contributing to the app.

### Requirements

- See `.ruby-version` file for required Ruby version
- PostgreSQL >9.3 (ideally, latest stable version)

After cloning the repo, the basic setup commands are:

```sh
cd <your-clone-directory>
cp .env.local.example .env.local
bin/setup
bin/dev

# Optionally, load demo data
rake demo_data:default
```

And visit http://localhost:3000 to see the app. If you loaded the demo data (an Indian household
of an NRI husband and a resident wife, with NRE/NRO and savings accounts, card, demat, mutual funds, EPF/PPF, an FD, a home loan, insurance and goals),
you can log in (as Rahul, the NRI) with:

- Email: `user@example.com`
- Password: `password`

For further instructions, see guides below.

### Setup Guides

- [Mac dev setup guide](https://github.com/maybe-finance/maybe/wiki/Mac-Dev-Setup-Guide)
- [Linux dev setup guide](https://github.com/maybe-finance/maybe/wiki/Linux-Dev-Setup-Guide)
- [Windows dev setup guide](https://github.com/maybe-finance/maybe/wiki/Windows-Dev-Setup-Guide)
- Dev containers - visit [this guide](https://code.visualstudio.com/docs/devcontainers/containers) to learn more
