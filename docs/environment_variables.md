# Environment variables

New environment variables of the API are documented here, in the PR that adds them: name, purpose, default and an example. Older variables are not all listed yet.

Sensitive values (keys, secrets, passwords, tokens, credentials embedded in URLs) are always masked in examples, e.g. `LAGO_SMTP_PASSWORD=***` or `DATABASE_URL=postgresql://***@db:5432/lago`.

## Redis

- `LAGO_REDIS_SIDEKIQ_SENTINEL_USERNAME`: optional ACL username for Sidekiq Redis Sentinel authentication. Used only when `LAGO_REDIS_SIDEKIQ_SENTINELS` is configured; blank leaves the username unset. Omit for password-only authentication. Example: `LAGO_REDIS_SIDEKIQ_SENTINEL_USERNAME=sentinel`
- `LAGO_REDIS_SIDEKIQ_SENTINEL_PASSWORD`: optional password for Sidekiq Redis Sentinel authentication, separate from the data Redis password (`REDIS_PASSWORD`). Used only when `LAGO_REDIS_SIDEKIQ_SENTINELS` is configured; blank leaves the password unset. Example: `LAGO_REDIS_SIDEKIQ_SENTINEL_PASSWORD=***`
- `LAGO_REDIS_CACHE_SENTINEL_USERNAME`: optional ACL username for cache Redis Sentinel authentication. Used only when `LAGO_REDIS_CACHE_SENTINELS` is configured; blank leaves the username unset. Omit for password-only authentication. Example: `LAGO_REDIS_CACHE_SENTINEL_USERNAME=sentinel`
- `LAGO_REDIS_CACHE_SENTINEL_PASSWORD`: optional password for cache Redis Sentinel authentication, separate from the data Redis password (`LAGO_REDIS_CACHE_PASSWORD`). Used only when `LAGO_REDIS_CACHE_SENTINELS` is configured; blank leaves the password unset. Example: `LAGO_REDIS_CACHE_SENTINEL_PASSWORD=***`

## Runtime and workers

- `LAGO_ENABLE_YJIT`: when true, enables YJIT (`config.yjit`). Disabled by default. Example: `LAGO_ENABLE_YJIT=true`
- `SIDEKIQ_WALLETS`: when true, wallet jobs (e.g. `Customers::RefreshWalletJob`) are routed to the `wallets` queue, processed by the dedicated wallet worker (`scripts/start.wallets.worker.sh`). Example: `SIDEKIQ_WALLETS=true`
- `SIDEKIQ_AI_AGENT`: when true, AI conversation jobs (`AiConversations::StreamJob`) are routed to the `ai_agent` queue. Example: `SIDEKIQ_AI_AGENT=true`
- The `streaming` queue (`config/sidekiq/sidekiq_streaming.yml`, `scripts/start.streaming.worker.sh`) has no `SIDEKIQ_*` flag on purpose. `DeliverEventJob` is pinned to it unconditionally, because its worker needs an AWS identity the general workers do not have, and a wallet-refresh burst arrives as one job per customer and must not compete with billing work. Nothing is enqueued unless the organization has a `streaming_destinations` row, so a deployment that runs no streaming worker never fills the queue.
- `LAGO_STREAMING_INTERMEDIATE_ROLE_ARN`: IAM role that a streaming worker assumes before it assumes the destination role of a `streaming_destinations` row. Set it when the worker's own Pod Identity role is not the principal the destination trusts: the destination then sees this role as the caller, so the trust policy of the stream owner needs no change. Blank keeps the single-hop path, where the worker assumes the destination role directly from its ambient credentials. The value is read at class load, so a worker must restart before a change takes effect. Example: `LAGO_STREAMING_INTERMEDIATE_ROLE_ARN=arn:aws:iam::123456789012:role/SharedKinesis`
- `LAGO_KARAFKA_METRICS_PORT`: when set, the Karafka process serves its Prometheus metrics on that port, on all interfaces. A consumer process serves no Rack app, so without it nothing the consumers measure is scrapable, while the Rails `/metrics` route keeps covering the web processes. Blank leaves the exporter off. Example: `LAGO_KARAFKA_METRICS_PORT=9394`

## Usage

- `LAGO_REALTIME_USAGE_ENABLED`: when true, allows current usage to be served from the pre-aggregated ClickHouse usage buckets. The value is cast as a boolean, so `false` or `0` disables serving. Deployment-wide kill switch: serving also requires a premium license, `LAGO_CLICKHOUSE_ENABLED`, the organization reading the ClickHouse events store, and the per-organization `realtime_usage` feature flag. Example: `LAGO_REALTIME_USAGE_ENABLED=true`
- `LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC`: Kafka topic carrying one trigger per enriched count/sum event, keyed by `(organization_id, customer_id)`. Shared by every reaction to freshly ingested usage, each of which consumes it under its own consumer group; wallet refresh (`WalletRefreshTriggersConsumer`) is the only one today. When blank the topic is not routed and no reaction runs, leaving wallet refresh entirely to the five-minute `Clock::RefreshWalletsOngoingBalanceJob` sweep. Example: `LAGO_KAFKA_REALTIME_USAGE_TRIGGERS_TOPIC=realtime_usage_triggers`

## API

- `LAGO_API_TOTAL_COUNT_TIMEOUT_MS`: statement timeout, in milliseconds, of the count behind `include_total_count` on cursor-paginated v2 lists. When the count times out, the total falls back to the planner's row estimate, flagged with `total_count_estimated`. Defaults to 2000. Example: `LAGO_API_TOTAL_COUNT_TIMEOUT_MS=2000`

## Email

- `LAGO_SMTP_AUTHENTICATION`: SMTP authentication method, one of `login` (default), `plain`, `cram_md5` or `xoauth2`. `none` or `disabled` turn authentication off and drop `LAGO_SMTP_USERNAME`/`LAGO_SMTP_PASSWORD` from the mailer settings, which is required because net-smtp authenticates with PLAIN as soon as a username is present; use it only for a trusted self-hosted relay. A blank value keeps the default, so a variable left empty by a compose file or a Helm chart cannot silently change authentication. Any other value makes every delivery fail, and `rails lago:diagnostics` flags it. Example: `LAGO_SMTP_AUTHENTICATION=none`
- `LAGO_SMTP_ENABLE_STARTTLS_AUTO`: whether SMTP automatically uses STARTTLS. Defaults to true; set it to false only for a trusted self-hosted relay without TLS. Example: `LAGO_SMTP_ENABLE_STARTTLS_AUTO=false`

## Webhooks

- `LAGO_WEBHOOK_ALLOW_PRIVATE_URLS`: when true, webhook endpoints and the Okta/Entra ID hosts may point at private, loopback, link-local or other reserved addresses. Blocked by default: the host is resolved when the webhook URL is saved and again on every request, and the connection is pinned to the checked IP. Self-hosted deployments delivering webhooks to internal hosts must set it. Example: `LAGO_WEBHOOK_ALLOW_PRIVATE_URLS=true`

## Integrations

- `LAGO_ANROK_DRAFT_TAXES_CACHE_TTL_SECONDS`: how long, in seconds, an Anrok answer to a draft tax request is reused for an identical request (`Integrations::Aggregator::Taxes::Invoices::DraftTaxesCacheService`). It bounds how long a draft can lag behind a change made on the Anrok side (registration, exemption certificate, rate). Finalized invoices are never cached. Defaults to 86400 (1 day); 0 disables the cache, reads included, so entries already stored stop being served. Example: `LAGO_ANROK_DRAFT_TAXES_CACHE_TTL_SECONDS=86400`
- `LAGO_FINANCE_ASSISTANT_URL`: base URL of the finance assistant service that answers `askFinanceAssistant`. When blank the feature is unavailable and the mutation returns a forbidden failure. Example: `LAGO_FINANCE_ASSISTANT_URL=http://lago-data-agent:8000`
- `LAGO_FINANCE_ASSISTANT_OPEN_TIMEOUT`: connection timeout, in seconds, for the finance assistant call. Defaults to 5. Example: `LAGO_FINANCE_ASSISTANT_OPEN_TIMEOUT=5`
- `LAGO_FINANCE_ASSISTANT_READ_TIMEOUT`: response timeout, in seconds, for the finance assistant call. Defaults to 60. Must stay above the assistant's own run deadline (`ASK_DEADLINE_SECS`, 55s today) so that a slow answer is received instead of being cut off. Example: `LAGO_FINANCE_ASSISTANT_READ_TIMEOUT=60`
- `LAGO_X402_RPC_URLS`: JSON object mapping a CAIP-2 network to the JSON-RPC endpoint the x402 chain readers (`X402::Chain::EvmReader`, `X402::Chain::SvmReader`) use to learn whether a settlement whose answer was lost moved the money. Networks it omits keep the public endpoints: `eip155:8453` https://mainnet.base.org, `eip155:84532` https://sepolia.base.org, `solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp` https://api.mainnet-beta.solana.com and `solana:EtWTRABZaYq6iMfeYKouRu166VU2xqa1` https://api.devnet.solana.com. Those are rate limited, so production should set a provider URL per network. It is read on every call; invalid JSON raises. Example: `LAGO_X402_RPC_URLS={"eip155:8453":"https://base-mainnet.g.alchemy.com/v2/***"}`
- `CS_ADMIN_SLACK_WEBHOOK_URL`: Slack incoming webhook the CS admin panel posts audit log notifications to (`Admin::SlackNotificationService`). When blank, no notification is sent. Example: `CS_ADMIN_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/***`
