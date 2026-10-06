---
name: statement-import
description: >
  Import new transactions into MoneyMatter from files dropped in `.temp/` – CSV, PDF statements
  or screenshots – adding only transactions that are not in the app yet. Five targets:
  1) Telegram Wallet screenshots → "Telegram" + "Gram stake" investment portfolios,
  2) ZEN.COM statements (CSV/PDF) → the ZEN bank accounts (EUR / PLN / USD),
  3) Tonkeeper screenshots → "Tonkeeper" + "Gram stakee" investment portfolios,
  4) Interactive Brokers screenshots (trades + portfolio) → "Interactive Brokers" portfolio,
  5) Freedom Finance / Freedom24 screenshots (cash flow + portfolio) → "Freedom Finance" portfolio.
  Trigger on "/statement-import", "імпортуй", "імпорт виписки", "import statement",
  "import screenshots", "додай транзакції з файлів".
---

Import transactions from files in `.temp/` (gitignored) into the user's local MoneyMatter.

**Write path.** Prefer the **MoneyMatter MCP server** tools (`get_accounts`, `search_transactions`, `create_transaction`, `get_portfolios`, `get_portfolio_holdings`, `get_investment_transactions`, `search_securities`, `create_investment_transaction`; prefix usually `mcp__moneymatter__…`). If they are not loaded, use the app's REST API from the user's logged-in browser tab (`https://localhost:8100`, API at `https://localhost:8081/api/v1`, `fetch(..., {credentials:'include'})`) – the user approved this fallback. Never read `.env` files or write to the database directly.

The user's standing decisions – follow them, don't re-ask:

- **Always ask the target** (step 1–2). Never guess the account/portfolio from the file alone.
- **No plan confirmation** – once the target is chosen, import straight away and report afterwards. Exception: clearing/rebuilding existing data – run the `db-backup` skill first and confirm.
- **Only new transactions** – detect existing ones by date + amount + description (step 4).
- **Ask about non-standard income.** The user's known regular income sources live in your memory, not in this repo. Any other incoming money (transfers from people, payment-service payouts, refunds, cash deposits, unknown senders) must not be classified as income or transfer on your own. List those rows (date, amount, account, description) in one question and record them the way the user says. ATM cash deposits are always asked about. A deposit can be unspent withdrawn cash coming back → `transfer_out_wallet` (the withdrawal was one too). It can also be USD cash exchanged to PLN → `transfer_out_wallet`. ATM withdrawals are not expenses → `transferNature: 'transfer_out_wallet'` (cash is tracked only as a balance on the "Готівка" accounts).
- **Delete the source files from `.temp/` after a successful, verified import.**
- **The app is the only source of truth** – never compare with or re-read the CoinGecko website portfolios.
- **GRAM = TON** (renamed). Same coin: CoinGecko id `the-open-network` (website slug `gram`), Binance `TONUSDT` (older) / `GRAMUSDT` (after the rename).

## 1. Ask what the import is for

Ask exactly this (plain text, the user answers with a number):

> Для чого імпорт?
> 1 — Telegram (скріншоти Telegram Wallet → портфелі «Telegram» і «Gram stake»)
> 2 — ZEN (CSV / PDF виписка → рахунки ZEN EUR / PLN / USD)
> 3 — Tonkeeper (скріншоти Tonkeeper → портфелі «Tonkeeper» і «Gram stakee»)
> 4 — Interactive Brokers (скріншоти IBKR Orders & Trades + Portfolio → портфель «Interactive Brokers»)
> 5 — Freedom Finance (скріншоти Freedom24 Cash flow + Portfolio → портфель «Freedom Finance»)

Then list the files currently in `.temp/` (ignore `.temp/backups/`) and ask which of them belong to this import if it is not obvious.

## 2. Confirm the exact target

- **1 → Telegram:** portfolios `Telegram` (wallet, including USDT held in Earn) and `Gram stake` (only GRAM staked via Telegram Wallet **Earn**). If either is missing, stop and say so.
- **2 → ZEN:** accounts `ZEN EUR`, `ZEN PLN`, `ZEN USD`; a ZEN statement is per currency – confirm which account each file is for. A missing account can be created (`POST /accounts` with `name`, `currencyCode`, `initialBalance` = statement opening balance) – say so in the report.
- **3 → Tonkeeper:** portfolios `Tonkeeper` (wallet) and `Gram stakee` (staking via Stakee / staking contracts). Create a missing one (`POST /investments/portfolios`, `portfolioType: 'investment'`) and say so.

- **4 → Interactive Brokers:** portfolio `Interactive Brokers` (create if missing). Unlike crypto wallets, a broker holds **real cash** – model deposits and FX, and do NOT zero the cash in step 7.

## 3. Read the files into normalized rows

Read every file yourself with the Read tool (it handles PDF and images). Do not use the app's AI parser. Write the rows to a scratchpad file and verify them with a script before importing.

**ZEN CSV / PDF** → `{ date, amount, direction, currency, description, balanceAfter }`.

- Verify the running balance against the statement's balance column row by row, and the totals against "Total income / outcome / closing balance". Fix transcription until there are zero mismatches.
- Skip pending/declined/cancelled rows. Use the transaction date (not booking date) for card payments.

**Telegram Wallet / Tonkeeper screenshots** → `{ datetime (user's local timezone), type, asset, quantity, note }`. Screenshots overlap – deduplicate rows that appear at the bottom of one and the top of the next; flag suspected gaps between screenshots in the report.

- Received / Top-up / P2P purchase / Bonus / Gift / Payout / Allocation / "Claim from Earn" → `IN`.
- Sent / Withdrew / Transfer to DeFi / Call contract with an amount → `OUT`.
- **Monthly income in Telegram Wallet** – a recurring USDT "Top-up from <address>" once a month (sometimes split into two top-ups in the same month) → `INCOME`: the user's income, not a trade. Import three records with the same date and amount: (1) buy USDT at price 1 in `Telegram`; (2) an income transaction on the pass-through account `Telegram Wallet` (USD) – `transactionType: 'income'`, `transferNature: 'not_transfer'`, `paymentType: 'bankTransfer'`, category "Зарплата, рахунки", `time` `${date}T12:00:00.000Z`, note "Income: USDT top-up from <address> (Telegram Wallet)"; (3) `POST /investments/portfolios/:id/transfer/from-account` from that account to `Telegram`. Only account transactions reach the Income/Expense stats – a portfolio `cash-transaction` deposit never shows as income, so don't use it here. The account stays at 0; the transfer cancels the buy's cash effect, so the step 7 cash-zeroing never offsets it. P2P purchases, refunds and exchanges are not income. Ask if a top-up doesn't clearly fit the pattern.
- "Exchanged USDT to X" → `EXB` (only the received side is shown).
- "Exchanged X to USDT" → `EXS` (USDT received is shown).
- Pre-order (−USDT), pre-order refund (+USDT), Allocation (+asset) → price = (USDT paid − refund) / allocated quantity.
- Telegram "Transfer to Earn" / "Transfer from Earn" of **GRAM** → `EARN_TO` / `EARN_FROM` (moves to/from `Gram stake`). `Gram stake` holds **only staked GRAM** – USDT (or any other coin) sent to Earn stays in the `Telegram` portfolio: skip those rows (no transaction at all).
- Tonkeeper "Stake" (−GRAM, +STAKED) or Call contract to a staking pool → `STAKE_TO`; unstake / pool payout → `STAKE_FROM`.
- Fragment auction **Bid** rows show no amount: the matching later "Received" refund equals that bid. The winning bid has no refund – derive it from the reconciliation (step 6).
- Skip: Canceled / Failed rows, NFTs, "Unknown" operations, spam / unverified tokens, and airdrop tokens that are fully exchanged or worthless – list them in the report.
- A value that is unreadable or cut off: ask the user instead of guessing. A truncated time ("at 2:…") → use noon of that day.

**Interactive Brokers screenshots** (IBKR mobile → Orders & Trades → Trades, one quarter per filter; plus Portfolio → Positions/Cash for reconciliation):

- Each row: symbol + exchange, `Bought`/`Sold` quantity, fill price, amount, commission (small grey line), time; date comes from the section header. The header shows "N Trade(s)" – count your rows per quarter and ask for missing screenshots if the count is lower.
- The trade list is per quarter: ask the user for **every quarter** since the account was opened (switch the quarter filter). Positions on the Portfolio screen must equal the sum of all trades.
- The IBKR mobile app may return only recent history. When the user confirms nothing older is available, reconcile with derived entries (the user approved this): missing quantity per symbol = Portfolio position − traded quantity; total cost of the missing lots = (MKT VAL − UNREALIZED P&L) − cost of the visible trades (incl. commissions). Price a missing lot at the nearest known fill price of that symbol, and give the remainder to the symbol without a nearby fill so the total cost matches. Missing USD = derive a deposit so final USD cash equals "Total Cash". Date these just before the earliest visible trade and say "derived" in `name`/`description`.
- Stocks/ETFs → `buy`/`sell` with the exact fill price, quantity and commission as `fees` (already exact – no market-price lookup).
- `EUR.USD` rows are currency conversions, not securities:
  - A large plain conversion (e.g. "Sold X EUR.USD" for $Y with a commission) = the user's EUR deposit converted to USD → record a portfolio **deposit** of the EUR amount (`cash-transaction` `deposit`, currency EUR) and an **exchange** EUR→USD (`POST /investments/portfolios/:id/exchange-currency`) with the USD received, and the commission as a fee.
  - `AFx` (auto-FX) rows come in pairs (Sold X EUR + Bought ~X EUR within the same second) around a stock buy – they net to a few cents; record only the net USD difference as a fee, not as separate conversions.
  - "Other" rows at 23:00 with tiny amounts (0.0036…) are end-of-day rounding – skip.
- Deposits/withdrawals are not in the Trades list: ask the user for the Transactions/Funding history screenshot or the deposit amounts and dates.
- Securities: stocks come from the app's stock provider (search `assetClass=stocks`). If search returns nothing (Yahoo can be blocked by EU consent redirects), ask the user to add an `FMP_API_KEY`/`ALPHA_VANTAGE_API_KEY`, or create the holding from a manual `searchResult` (`symbol`, `providerSymbol` = ticker, `providerName: 'yahoo'`, `assetClass: 'stocks'`, `currencyCode: 'USD'`) and warn that prices won't update until the provider works.
- Reconcile: positions per symbol and **USD cash** must equal the Portfolio screen ("Total Cash"); Net Liquidation Value ≈ app portfolio total.

**Freedom Finance (Freedom24) screenshots** – "Cash flow" (Menu → Reports/Cash flow, scrolled through the whole history) plus Portfolio (net asset valuation, USD cash, every "Opened positions" row: ticker, "N pcs by AVG", last price, value):

- Volume: often 100+ screenshots. Transcribe them with parallel subagents (~28 files each) into TSV (`file, date, time, title, amount, currency, description`) plus a per-file list of date headers with their day totals. Files are numbered oldest → newest, but inside a screenshot dates go newest → oldest; a row cut at the top belongs to the **oldest header of the next file**.
- Row types: `Card payment` / `Bank transfer` (deposit), `Other fees` "Комісія за поповнення рахунку. Дата D" (2.5 % deposit fee), `Trading fee` "(Trade ID buy TICKER.US)", `Dividends` / `Taxes` "(TICKER.US) record date D", `The agent's fees on dividend`, `Split` / `Compensation for corporate action` (cash in/out), occasional EUR rows.
- **The Cash flow has no buy/sell amounts** (only their commissions). Positions therefore come from the Portfolio screen: one `buy` per ticker, quantity = current position, price = the shown average ("by AVG"), dated at the ticker's first `Trading fee`. A position with average 0 (e.g. a spin-off) → buy at price 0. Tickers that appear in fees but not in positions (closed/merged positions, funds) are not created – their fees go to cash.
- **Dedup by semantic keys, not by screen position**: trading fee → trade id; dividend/tax/agent fee → ticker + record date; deposit fee → its "Дата" + amount; deposit → date + time + amount. Rows without a key (cut off) only fill gaps. Genuinely identical rows exist (several 150 USD deposits the same day) – validate every day against its header total and fix counts where the difference is a whole number of deposit(+fee) or a missing dividend; differences that cancel between adjacent days are just misattributed rows.
- Import: deposits / deposit fees / corporate-action compensations / fees of closed tickers → portfolio `cash-transaction` (deposit/withdrawal); EUR deposit → EUR deposit + `exchange-currency` to the USD amount implied by the day total; dividends → `dividend`, taxes → `tax`, trading/agent fees → `fee` (all with `quantity: "1"`, `price` = amount, on the ticker's holding).
- Reconcile: final USD cash must equal the Portfolio "Cash USD"; post one `isAdjustment` withdrawal/deposit for the remainder and name its likely causes. Holdings value should match "Opened positions" (non-USD funds can't be priced – mention them).

## 4. Prices (screenshots have none)

Price every investment row at the time of the operation, in USD:

- **USDT** = 1.
- **GRAM from 2024-08-08, BTC and other Binance-listed coins**: Binance 1h klines, close of the candle containing the time (`/api/v3/klines?symbol=TONUSDT|GRAMUSDT|BTCUSDT&interval=1h`).
- **GRAM before 2024-08-08**: CoinGecko website daily close via the logged-in browser – `https://www.coingecko.com/en/coins/gram/historical_data?start=D&end=D` (query one day at a time; ranges paginate). If a day is missing, interpolate between the nearest known days and say so.
- **xStocks and other tokens not on Binance**: CoinGecko API `market_chart/range` (Demo key only serves the last 365 days; call it inside the backend container so the key isn't printed), nearest point.
- `EXB` USDT spent = quantity × price (estimate – note "(USDT spent, est.)"). `EXS` price = USDT received / quantity.

## 5. Keep only new transactions

Work per target over the date range covered by the rows.

**ZEN (bank account):**

1. Fetch the account's transactions for [earliest row − 1 day, latest row + 1 day], paging until exhausted.
2. A row matches an existing transaction when: same calendar day, same amount (to the cent), same direction, and the description is the same or one contains the other (case-insensitive). Each existing transaction matches at most one row. Rows older than the latest existing transaction with no match are gaps and **are** imported.

**Portfolios:** match on same day, same security, same side, quantity within 1e-8, one-to-one. A two-leg move (Earn / Stake) is imported only if **both** legs exist; create the missing leg otherwise.

## 6. Import

**ZEN:**

- Card payments / fees / outgoing transfers / refunds → `create_transaction` (or `POST /transactions`) income/expense, `transferNature: 'not_transfer'`, `paymentType` `debitCard` or `bankTransfer`, `time` = `${date}T12:00:00.000Z`, `note` = description. The API requires `categoryId` for these – use the internal "Інше" category; the user recategorizes.
- **Currency exchanges between ZEN accounts** (EUR↔PLN↔USD) → one transfer: `transferNature: 'transfer_between_user_accounts'`, `accountId` = source, `amount` = source amount, `destinationAccountId`, `destinationAmount`. Match both sides by date + amounts; if the other side's statement is missing, record `transfer_out_wallet` and replace it with a transfer once that statement arrives.
- **"ZEN account top-up" (EUR)** – crypto sent from Telegram Wallet → income with `transferNature: 'transfer_out_wallet'`, note "ZEN account top-up from Telegram Wallet (crypto), fee X EUR" (settlement amount = net).

**Portfolios** (`POST /investments/holding` for each security first, then `create_investment_transaction` / `POST /investments/transaction` with `portfolioId`, `securityId`, `category`, ISO `date`, string `quantity`, `price`, `fees: "0"`, `name` = note):

- `IN` → buy; `OUT` → sell; `EXB` → buy X + sell USDT; `EXS` → sell X + buy USDT; allocation → buy at the derived price.
- **Moves between portfolios** – the `transfer` category changes neither quantity nor cash, so never use it. Record two legs with the same date, quantity and price: `EARN_TO` = sell `Telegram` + buy `Gram stake`, `EARN_FROM` = the reverse; `STAKE_TO` = sell `Tonkeeper` + buy `Gram stakee`, `STAKE_FROM` = the reverse.
- **Staking rewards** → buy in the staking portfolio at price `0` (no cash). Unstake more than staked → reward = returned − staked, dated just before the unstake. Current rewards → from the user's staking screenshot (e.g. Stakee "Staking balance" = STAKED × exchange rate), reward = balance − staked. STAKED/LST tokens are modeled as their GRAM equivalent (the app can't price them).

Create sequentially. If a call fails, stop, report which rows were created and which were not, and **do not delete any files**.

## 7. Verify, reconcile, clean up, report

1. Re-fetch and check every imported row has a match and nothing was created twice (for ZEN, count transactions per account in the report).
2. **Zero the portfolio cash (crypto wallets only – never for brokers: Interactive Brokers, Freedom Finance).** Imported buys/sells move the portfolio's fiat cash, but a crypto wallet holds no fiat (USDT is a holding). The portfolio total in the app = holdings value + cash, so leftover cash makes totals wrong (a wallet can show a tiny total instead of its real value). After importing, read the portfolio's USD `totalCash` and post one `POST /investments/portfolios/:id/cash-transaction` with `type` `deposit` (cash < 0) or `withdrawal` (cash > 0), the absolute amount, today's date, `isAdjustment: true`, description "Adjustment: crypto wallet has no fiat cash". Verify cash ≈ 0.
3. **Reconcile against reality:** ZEN – the account balance must equal the statement closing balance. Wallets – ask the user for a screenshot of the current wallet / staking balances; add one correction per asset for the difference (a derived winning bid, or `Correction: missing history (gap in screenshots)` at price 0) and explain it.
4. Compare the app's portfolio totals (holdings value) with the wallet's total the user sees, not just coin quantities.
5. Only if everything imported and reconciled: delete those source files from `.temp/`. Never delete `.temp/backups/`.
6. Report in Ukrainian: target, files, rows read, imported, skipped as existing, skipped on purpose (with reasons), price sources and estimates, corrections, final balances vs. reality, deleted files.
