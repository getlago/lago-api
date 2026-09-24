# frozen_string_literal: true

# x402 POC demo: an agent buys Lago credits with USDC over x402 and spends them, through the real CDP facilitator.
#   lago exec api bundle exec rails runner scripts/x402_poc/demo.rb [calls]   # drop "lago exec api" inside the container
# Each top-up is X402_POC_TOP_UP_CENTS; each call costs one credit (one cent), so the default 12 calls buy twice.

# rubocop:disable Rails/Output,Rails/Exit

require "net/http"
require_relative "config"
require_relative "eip3009_signer"

module X402Poc
  class Demo
    def initialize(calls:)
      @calls = calls
      @organization = X402Poc.organization
      @agent = Eip3009Signer.new(X402Poc.env!("X402_POC_BUYER_PRIVATE_KEY"))
    end

    def run
      puts "Agent #{agent.address} holds #{usdc_balance} USDC on #{X402Poc.network}"

      calls.times do |index|
        gate = gate_check
        gate = buy_credits(gate) if gate["requirements"]
        puts format("call %2d: gate passed with %s credits, metered on %s", index + 1, gate["balance_credits"], gate["external_subscription_id"])

        post_usage_event(gate.fetch("external_subscription_id"))
        refresh_wallets
      end

      summary
    end

    private

    attr_reader :calls, :organization, :agent

    def gate_check
      api_post("x402/gate_checks", gate_check: {
        connection_code: CONNECTION_CODE, wallet_code: WALLET_CODE, agent_address: agent.address,
        resource: "POST /v1/generate", plan_code: PLAN_CODE, billable_metric_code: METRIC_CODE,
        amount_cents: X402Poc.top_up_cents, estimated_call_cost_cents: 1
      }).fetch("gate_check")
    end

    def buy_credits(gate)
      entry = gate["requirements"].find { |requirement| requirement["network"] == X402Poc.network }
      puts "\nE7: 402 challenge, top up #{entry["amount_atomic"]} atomic USDC to #{entry["pay_to"]}"

      requirements, payment = sign_payment(entry)
      purchase = api_post("x402/credit_purchases", credit_purchase: {
        connection_code: CONNECTION_CODE, wallet_code: WALLET_CODE, plan_code: PLAN_CODE,
        payment:, payment_requirements: requirements,
        wallet: {name: "x402 POC credits", rate_amount: WALLET_RATE_AMOUNT, currency: "USD"}
      }).fetch("x402_settlement")
      puts "E8: #{purchase["status"]}, #{purchase["credits_granted"]} credits, #{explorer_url(purchase["transaction_hash"])}\n\n"

      if purchase["status"] == "settled"
        gate_check
      else
        abort("Purchase #{purchase["lago_id"]} is #{purchase["status"]}: see README, 'If a purchase stays pending'")
      end
    end

    # What lago-x402 renders into a v2 402: the network's USDC contract and EIP-712 domain, then the agent signs.
    def sign_payment(entry)
      asset = X402::Asset.fetch(code: entry["asset"], network: entry["network"])
      requirements = {
        "scheme" => entry["scheme"], "network" => entry["network"], "amount" => entry["amount_atomic"],
        "asset" => asset.address, "payTo" => entry["pay_to"], "maxTimeoutSeconds" => entry["max_timeout_seconds"],
        "extra" => {"name" => asset.eip712_name, "version" => asset.eip712_version}
      }
      authorization = {
        "from" => agent.address, "to" => entry["pay_to"], "value" => entry["amount_atomic"], "validAfter" => "0",
        "validBefore" => (Time.now.to_i + entry["max_timeout_seconds"]).to_s, "nonce" => "0x#{SecureRandom.hex(32)}"
      }
      signature = agent.sign_transfer_with_authorization(
        domain: {name: asset.eip712_name, version: asset.eip712_version,
                 chain_id: X402::Network.evm_chain_id(entry["network"]), verifying_contract: asset.address},
        message: authorization
      )

      [requirements, {"x402Version" => 2, "accepted" => requirements, "payload" => {"signature" => signature, "authorization" => authorization}}]
    end

    # A float timestamp: the subscription may have started earlier within the same second.
    def post_usage_event(external_subscription_id)
      api_post("events", event: {
        transaction_id: "x402-poc-#{SecureRandom.uuid}", code: METRIC_CODE, external_subscription_id:,
        timestamp: Time.current.to_f, properties: {target_wallet_code: WALLET_CODE}
      })
    end

    # The local deployment disables the refresh clock (LAGO_DISABLE_WALLET_REFRESH), so the demo refreshes itself;
    # the refresh a grant queues on Sidekiq may write the same wallet row concurrently, hence the retry.
    def refresh_wallets(attempts: 3)
      Customers::RefreshWalletsService.call!(customer:)
    rescue ActiveRecord::StaleObjectError
      attempts -= 1
      if attempts.positive?
        retry
      else
        raise
      end
    end

    def customer
      organization.customers.find_by!(x402_agent_address: agent.address)
    end

    def summary
      wallet = customer.wallets.active.find_by!(code: WALLET_CODE)
      puts "\nCustomer #{customer.external_id} (#{customer.id})"
      puts "Wallet #{wallet.code}: #{wallet.credits_balance} credits, #{wallet.credits_ongoing_balance} ongoing"
      organization.x402_settlements.where(customer:).order(:created_at).each do |settlement|
        puts "Settlement #{settlement.id}: #{settlement.status}, #{settlement.settled_amount_cents} cents, #{explorer_url(settlement.transaction_hash)}"
      end

      sleep 5 # phase 2 runs on Sidekiq
      customer.invoices.where(invoice_type: :credit).order(:created_at).each do |invoice|
        payment = invoice.payments.order(:created_at).last
        puts "Credit invoice #{invoice.number}: #{invoice.payment_status}, #{payment&.payment_type} #{payment&.provider_payment_id}"
      end
    end

    def usdc_balance
      asset = X402::Asset.fetch(code: "usdc", network: X402Poc.network)
      call = {to: asset.address, data: "0x70a08231#{agent.address.delete_prefix("0x").downcase.rjust(64, "0")}"} # balanceOf
      body = {jsonrpc: "2.0", id: 1, method: "eth_call", params: [call, "latest"]}
      response = Net::HTTP.post(URI(X402Poc.rpc_url), body.to_json, "Content-Type" => "application/json")

      Integer(JSON.parse(response.body).fetch("result"), 16).fdiv(10**asset.decimals)
    end

    def explorer_url(transaction_hash)
      host = (X402Poc.network == "eip155:8453") ? "basescan.org" : "sepolia.basescan.org"
      "https://#{host}/tx/#{transaction_hash}"
    end

    def api_post(path, body)
      response = Net::HTTP.post(URI("#{LAGO_API_URL}/#{path}"), body.to_json,
        "Content-Type" => "application/json", "Authorization" => "Bearer #{API_KEY}")

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        abort("POST #{path}: HTTP #{response.code} #{response.body}")
      end
    end
  end
end

X402Poc::Demo.new(calls: Integer(ARGV.first || 12)).run
# rubocop:enable Rails/Output,Rails/Exit
