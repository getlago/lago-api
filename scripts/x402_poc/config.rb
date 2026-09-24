# frozen_string_literal: true

# rubocop:disable Rails/Exit

require "dotenv"

# Keep SQL and httplog debug lines out of the scripts' output.
Rails.logger.level = :warn
HttpLog.configure { |config| config.enabled = false } if defined?(HttpLog)

Dotenv.load(File.expand_path(".env", __dir__))

module X402Poc
  # Hooli and its key are fixed by db/seeds/01_base.rb, so they are the same on every seeded dev database.
  ORGANIZATION_ID = "11111111-2222-3333-4444-555555555555"
  API_KEY = "lago_key-hooli-1234567890"
  # The scripts run inside the api container (lago exec api …), where the dev server is on localhost:3000.
  LAGO_API_URL = "http://localhost:3000/api/v1"
  # Running them outside the container (a native Rails setup on the host)? Go through Traefik instead:
  # LAGO_API_URL = "https://api.lago.dev/api/v1"

  CONNECTION_CODE = "x402_poc_base_sepolia"
  PLAN_CODE = "x402_poc_agent_api"
  METRIC_CODE = "x402_poc_calls"
  WALLET_CODE = "x402_poc_credits"
  CALL_PRICE = "0.01" # USD per call, the plan's standard charge
  WALLET_RATE_AMOUNT = "0.01" # USD per credit: one credit pays one call

  module_function

  def env!(name)
    ENV[name].presence || abort("Missing #{name}: fill in scripts/x402_poc/.env (see .env.example)")
  end

  def network = ENV["X402_POC_NETWORK"].presence || "eip155:84532"

  def top_up_cents = Integer(ENV["X402_POC_TOP_UP_CENTS"].presence || "10")

  def rpc_url = ENV["X402_POC_RPC_URL"].presence || "https://sepolia.base.org"

  def organization = Organization.find(ORGANIZATION_ID)
end
# rubocop:enable Rails/Exit
