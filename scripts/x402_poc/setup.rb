# frozen_string_literal: true

# x402 POC setup: feature flag, billable metric, usage-only plan and CDP connection for Hooli (seeded dev org).
#   lago exec api bundle exec rails runner scripts/x402_poc/setup.rb   # from a host; drop "lago exec api" inside the container
# Dev tooling: writes the connection directly, since connection CRUD (E1–E5) is out of POC scope.

# rubocop:disable Rails/Output

require_relative "config"
require_relative "eip3009_signer"

# Read every required value first, so a half-filled .env aborts before anything is written.
cdp_api_key_id = X402Poc.env!("X402_POC_CDP_API_KEY_ID")
cdp_api_key_secret = X402Poc.env!("X402_POC_CDP_API_KEY_SECRET")
payout_address = X402::Network.checksum(X402Poc.env!("X402_POC_PAYOUT_ADDRESS"))
agent = X402Poc::Eip3009Signer.new(X402Poc.env!("X402_POC_BUYER_PRIVATE_KEY"))

organization = X402Poc.organization
organization.enable_feature_flag!(:x402_payments) unless organization.feature_flag_enabled?(:x402_payments)

metric = organization.billable_metrics.find_by(code: X402Poc::METRIC_CODE) ||
  BillableMetrics::CreateService.call!(
    organization_id: organization.id, name: "x402 POC calls", code: X402Poc::METRIC_CODE, aggregation_type: "count_agg"
  ).billable_metric

# §16.2: agent plans are usage-only — no base fee, one standard charge per call. D16: the charge accepts a target
# wallet, so the route's fees can only drain the gated wallet (Hooli has events_targeting_wallets).
plan = organization.plans.parents.find_by(code: X402Poc::PLAN_CODE) ||
  Plans::CreateService.call!({
    organization_id: organization.id, name: "x402 POC agent API", code: X402Poc::PLAN_CODE,
    interval: "monthly", amount_cents: 0, amount_currency: "USD", pay_in_advance: false,
    charges: [{billable_metric_id: metric.id, charge_model: "standard", accepts_target_wallet: true, properties: {amount: X402Poc::CALL_PRICE}}]
  }).plan

connection = organization.x402_connections.find_or_initialize_by(code: X402Poc::CONNECTION_CODE)
connection.update!(
  name: "x402 POC (#{X402Poc.network})",
  networks: [X402Poc.network],
  payout_addresses: {"evm" => payout_address},
  cdp_api_key_id:,
  cdp_api_key_secret:
)

# Hooli enforces API-key permissions (api_permissions), and its seeded key predates the x402 resource.
api_key = organization.api_keys.find_by!(value: X402Poc::API_KEY)
api_key.update!(permissions: api_key.permissions.merge("x402" => %w[read write])) unless api_key.permit?("x402", "write")

puts <<~SUMMARY
  x402 POC ready for #{organization.name} (#{organization.id})
    connection  #{connection.code}: pays #{payout_address} on #{X402Poc.network}
    plan        #{plan.code}: #{X402Poc::CALL_PRICE} USD per #{metric.code} event, no base fee
    agent       #{agent.address} (needs Base Sepolia USDC)
  Next: lago exec api bundle exec rails runner scripts/x402_poc/demo.rb
SUMMARY
# rubocop:enable Rails/Output
