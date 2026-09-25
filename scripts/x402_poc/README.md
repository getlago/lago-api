# x402 POC — agents buy Lago credits with USDC

This POC runs two endpoints from the x402 backend design ("[BE] Agentic Payments — x402 via Coinbase CDP", the "Lago settles" version) against the real Coinbase CDP facilitator on Base Sepolia:

- **E7 `POST /api/v1/x402/gate_checks`**: asks whether the agent has credits. The answer is either a pass, carrying the `external_subscription_id` to meter the call with, or a top-up challenge. It creates nothing.
- **E8 `POST /api/v1/x402/credit_purchases`**: Lago verifies the agent's signed EIP-3009 payment with CDP, writes a `pending` settlement, settles, then finds or creates the customer, subscription and wallet and grants the credits at once. A credit invoice paid by an `x402` payment, and its receipt, follow asynchronously.

`demo.rb` plays the two parties the POC has no code for: the `lago-x402` middleware and the agent. It asks E7, signs the USDC authorization locally, buys through E8, meters each call with a usage event, and buys again when the credits run out.

Out of POC scope: the reservation counter, most of E7's route and state checks, replayed payments, reconciliation of `pending` settlements, Solana, connection CRUD, OpenAPI.

## Requirements

- The standard docker-compose dev stack with a **seeded** database. The scripts use the Hooli organization and its API key from `db/seeds/01_base.rb`.
- This branch's migrations: `lago exec api bundle exec rails db:migrate`.
- A **premium license**, since x402 is premium. Without one both endpoints answer `403 feature_unavailable`.
- Sidekiq running, for the credit invoice, the payment and the receipt.

## Where to run the scripts

**Always inside the api container**, from the host:

```bash
lago exec api bundle exec rails runner scripts/x402_poc/<script>.rb
```

Without the `lago` CLI, run the same command through Docker. The dev api container is `lago_api_dev`:

```bash
docker exec lago_api_dev bash -lc 'cd /app && bundle exec rails runner scripts/x402_poc/<script>.rb'
```

Inside the container, drop `lago exec api`. The rest of this README writes commands in the `lago exec api` form, and every one of them also runs as `docker exec lago_api_dev bash -lc 'cd /app && …'`.

The scripts need the app environment and OpenSSL 3.2 or newer for Keccak-256; the api image ships 3.5. They reach the API on `localhost:3000`. `https://api.lago.dev` does not work from inside the container: public DNS maps `*.lago.dev` to 127.0.0.1, and the container doesn't trust your mkcert certificate.

**Outside the container** (only with a native Rails setup on the host), switch `config.rb` to the commented-out `LAGO_API_URL = "https://api.lago.dev/api/v1"` line. If Ruby rejects the mkcert certificate, run with `SSL_CERT_FILE="$(mkcert -CAROOT)/rootCA.pem"`.

## Setup

1. `cp scripts/x402_poc/.env.example scripts/x402_poc/.env` (gitignored), then fill in the four values:
   - **CDP Secret API Key** id and secret, from the CDP portal. Ed25519 keys are pasted as given. ECDSA PEM keys go in double quotes with `\n` line breaks.
   - **Payout address**: any Base Sepolia EVM address you control.
   - **Agent private key**, one of:
     - Generate a fresh key: `lago exec api bundle exec rails runner 'puts "0x" + OpenSSL::PKey::EC.generate("secp256k1").private_key.to_s(16).rjust(64, "0")'`
     - Export the key of an already funded test account.
2. Fund the agent address with Base Sepolia USDC at https://faucet.circle.com. `setup.rb` prints the address. The agent needs no ETH: EIP-3009 is gasless for the payer, and the facilitator pays the gas.
3. Run `setup.rb`. It is safe to re-run: it enables `x402_payments`, and creates the `x402_poc_calls` metric, the usage-only `x402_poc_agent_api` plan (0.01 USD per call) and the CDP connection. It also grants the `x402` API-key permission.

## Run

```bash
lago exec api bundle exec rails runner scripts/x402_poc/demo.rb [calls]   # default 12
```

Each top-up is `X402_POC_TOP_UP_CENTS` (10 cents, so 10 credits at 0.01 USD per credit), and each call spends one credit. A default run therefore buys twice and spends 0.20 test USDC. Expect:

```
Agent 0x… holds 9.8 USDC on eip155:84532

E7: 402 challenge, top up 100000 atomic USDC to 0x<payout>
E8: settled, 10.0 credits, https://sepolia.basescan.org/tx/0x…

call  1: gate passed with 10.0 credits, metered on x402_0x…_x402_poc_agent_api
…
call 10: gate passed with 1.0 credits, …

E7: 402 challenge, top up 100000 atomic USDC to 0x<payout>
E8: settled, 10.0 credits, https://sepolia.basescan.org/tx/0x…

call 11: …
call 12: …

Customer x402_0x… (…)
Settlement …: settled, 10 cents, https://sepolia.basescan.org/tx/0x…
Credit invoice …: succeeded, x402 0x…
```

The local stack disables the wallet-refresh clock (`LAGO_DISABLE_WALLET_REFRESH`), so the demo refreshes the agent's wallets itself after each usage event.

## If a purchase stays pending

There is no reconciliation job in the POC. When a settle times out or CDP answers `settlement_pending`, E8 returns `status: pending` and the demo stops. Look the transaction up on https://sepolia.basescan.org, then resolve the settlement in a console:

```ruby
s = X402::Settlement.find("<lago_id>")
# it landed on chain:
s.update!(status: :settled, transaction_hash: "0x…")
X402::CreditPurchases::GrantService.call!(settlement: s)
# nothing landed and reconcile_after has passed:
s.update!(status: :failed)
```

## If a purchase settled but granted nothing

This happens when E8 answers an error after the transaction landed. Run `X402::CreditPurchases::GrantService.call!(settlement: X402::Settlement.find("<lago_id>"))`. It grants from the purchase settings stored with the settlement, at most once.
