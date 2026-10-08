# frozen_string_literal: true

require "rails_helper"

describe X402::CreditPurchases::GrantService do
  subject(:result) { described_class.call(settlement:) }

  let(:x402_connection) { create(:x402_connection) }
  let(:organization) { x402_connection.organization }
  let(:payer_address) { "0xf4a43B9cc729c9E4E139CB86808f48e3eD09Dcb2" }
  let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD") }
  let(:rate_amount) { "0.001" }
  let(:settled_amount_cents) { 1000 }
  let(:settled_amount_atomic) { settled_amount_cents * 10_000 }
  let(:purchase_settings) do
    {
      "plan_code" => "agent_api",
      "wallet_code" => "agent_credits",
      "wallet" => {"name" => "Agent credits", "rate_amount" => rate_amount, "currency" => "USD"}
    }
  end
  let(:settlement) do
    create(:x402_settlement, x402_connection:, payer_address:, settled_amount_atomic:, settled_amount_cents:, purchase_settings:)
  end

  before { plan }

  context "with a first purchase" do
    it "creates the agent's customer" do
      expect(result.settlement.customer).to have_attributes(x402_agent_address: payer_address, external_id: "x402_#{payer_address}")
    end

    it "opens the subscription" do
      expect(result.settlement.subscription).to have_attributes(plan:, external_id: "x402_#{payer_address}_agent_api", status: "active")
    end

    it "creates the wallet from the stored shape" do
      expect(result.settlement.wallet_transaction.wallet).to have_attributes(code: "agent_credits", rate_amount: BigDecimal("0.001"), x402_enabled: true)
    end

    it "records a settled x402 purchase" do
      expect(result.settlement.wallet_transaction).to have_attributes(
        source: "x402",
        transaction_type: "inbound",
        transaction_status: "purchased",
        status: "settled",
        credit_amount: BigDecimal("10000"),
        amount: BigDecimal("10"),
        invoice_requires_successful_payment: false
      )
    end

    it "credits the wallet" do
      expect(result.settlement.wallet_transaction.wallet.reload).to have_attributes(balance_cents: 1000, credits_balance: BigDecimal("10000"))
    end

    it "links the grant onto the settlement" do
      expect(settlement.reload).to have_attributes(customer: result.settlement.customer, subscription: result.settlement.subscription, wallet_transaction: result.settlement.wallet_transaction)
    end

    it "bills the purchase" do
      expect { result }.to have_enqueued_job(BillPaidCreditJob).with(instance_of(WalletTransaction), instance_of(Integer))
    end

    it "announces the wallet transaction" do
      expect { result }.to have_enqueued_job(SendWebhookJob).with("wallet_transaction.created", instance_of(WalletTransaction))
    end
  end

  context "with $10.00 at rate 0.0007" do
    let(:rate_amount) { "0.0007" }

    it "floors the credits" do
      expect(result.settlement.wallet_transaction.reload.credit_amount).to eq(BigDecimal("14285.71428"))
    end

    it "keeps the settled amount" do
      expect(result.settlement.wallet_transaction.reload.amount).to eq(BigDecimal("10"))
    end
  end

  context "with $10.50 at rate 0.001" do
    let(:settled_amount_cents) { 1050 }

    it "credits every cent" do
      expect(result.settlement.wallet_transaction.reload).to have_attributes(credit_amount: BigDecimal("10500"), amount: BigDecimal("10.5"))
    end
  end

  context "with sub-cent dust" do
    let(:settled_amount_atomic) { 10_000_001 }

    it "credits the stored cents" do
      expect(result.settlement.wallet_transaction.reload.credit_amount).to eq(BigDecimal("10000"))
    end
  end

  context "with a Solana settlement" do
    let(:x402_connection) { create(:x402_connection, :solana) }
    let(:settlement) do
      create(:x402_settlement, :solana, x402_connection:, settled_amount_atomic:, settled_amount_cents:, purchase_settings:)
    end

    it "keys the customer by the Solana address" do
      expect(result.settlement.customer.external_id).to eq("x402_TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")
    end
  end

  context "with an agent that already purchased" do
    let(:customer) { create(:customer, organization:, currency: "USD", external_id: "x402_#{payer_address}", x402_agent_address: payer_address) }
    let(:subscription) { create(:subscription, customer:, plan:, external_id: "x402_#{payer_address}_agent_api") }
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", rate_amount: "0.002", balance_cents: 500, credits_balance: 2500, x402_enabled: true) }

    before do
      subscription
      wallet
      allow(Subscriptions::CreateService).to receive(:call).and_call_original
    end

    it "credits the existing wallet at its own rate" do
      expect { result }.to change { wallet.reload.credits_balance }.from(2500).to(7500)
    end

    it "creates no customer" do
      expect { result }.not_to change(Customer, :count)
    end

    it "creates no wallet" do
      expect { result }.not_to change(Wallet, :count)
    end

    it "never takes the customer lock" do
      result

      expect(Subscriptions::CreateService).not_to have_received(:call)
    end
  end

  context "with a wallet outliving the subscription" do
    let(:customer) { create(:customer, organization:, currency: "USD", external_id: "x402_#{payer_address}", x402_agent_address: payer_address) }
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", rate_amount: "0.001", x402_enabled: true) }
    let(:steps) { [] }

    before do
      create(:subscription, :terminated, customer:, plan:, external_id: "x402_#{payer_address}_agent_api")
      wallet
      allow(X402::Wallets::ResolveService).to receive(:call!).and_wrap_original do |original, **kwargs|
        original.call(**kwargs).tap { steps << :wallet_locked }
      end
      allow(Subscriptions::CreateService).to receive(:call).and_wrap_original do |original, **kwargs|
        steps << :customer_locking
        original.call(**kwargs)
      end
    end

    it "locks the wallet before the customer" do
      result

      expect(steps).to eq(%i[wallet_locked customer_locking])
    end

    it "opens a new subscription" do
      expect(result.settlement.subscription).to have_attributes(external_id: "x402_#{payer_address}_agent_api", status: "active")
    end

    it "credits the existing wallet" do
      expect(result.settlement.wallet_transaction.wallet).to eq(wallet)
    end
  end

  context "with a granted settlement" do
    let(:granted_transaction) { create(:wallet_transaction) }
    let(:settlement) do
      create(:x402_settlement, x402_connection:, purchase_settings:, customer: granted_transaction.wallet.customer, subscription: create(:subscription), wallet_transaction: granted_transaction)
    end

    before { settlement }

    it "returns the grant" do
      expect(result.settlement.wallet_transaction).to eq(granted_transaction)
    end

    it "grants nothing" do
      expect { result }.not_to change(WalletTransaction, :count)
    end

    it "bills nothing" do
      expect { result }.not_to have_enqueued_job(BillPaidCreditJob)
    end
  end

  context "with a pending settlement" do
    let(:settlement) { create(:x402_settlement, :pending, x402_connection:, purchase_settings:) }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(base: ["settlement_not_grantable"])
    end

    it "creates no customer" do
      expect { result }.not_to change(Customer, :count)
    end
  end

  context "with an invoice payment" do
    let(:settlement) { create(:x402_settlement, :invoice_payment, x402_connection:) }

    it "returns a validation failure" do
      expect(result.error.messages).to eq(base: ["settlement_not_grantable"])
    end
  end

  context "with a deleted plan" do
    let(:plan) { create(:plan, organization:, code: "agent_api", amount_cents: 0, amount_currency: "USD", deleted_at: Time.current) }

    it "returns a not found failure" do
      expect(result.error.error_code).to eq("plan_not_found")
    end

    it "leaves no customer behind" do
      expect { result }.not_to change(Customer, :count)
    end
  end

  context "when linking the grant deadlocks" do
    before do
      allow(settlement).to receive(:update!).and_wrap_original do |_original, **attributes|
        settlement.assign_attributes(attributes)
        raise ActiveRecord::Deadlocked
      end
    end

    it "restores the settlement" do
      result

      expect(settlement).not_to be_changed
    end

    it "returns credit_grant_failed" do
      expect(result.error.code).to eq("credit_grant_failed")
    end

    it "rolls the grant back" do
      expect { result }.not_to change(WalletTransaction, :count)
    end

    it "leaves no customer behind" do
      expect { result }.not_to change(Customer, :count)
    end

    it "bills nothing" do
      expect { result }.not_to have_enqueued_job(BillPaidCreditJob)
    end

    it "announces nothing" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob).with("wallet_transaction.created", anything)
    end
  end

  context "when replayed after a deadlock" do
    before do
      attempts = 0
      allow(settlement).to receive(:update!).and_wrap_original do |original, **attributes|
        attempts += 1
        if attempts == 1
          settlement.assign_attributes(attributes)
          raise ActiveRecord::Deadlocked
        end

        original.call(**attributes)
      end
      described_class.call(settlement:)
    end

    it "grants exactly once" do
      expect { result }.to change(WalletTransaction, :count).by(1)
    end

    it "links the grant" do
      expect(result.settlement.reload.wallet_transaction).to be_present
    end
  end

  context "when the caller holds a transaction" do
    subject(:result) { ActiveRecord::Base.transaction { described_class.call(settlement:) } }

    it "refuses to run" do
      expect { result }.to raise_error(RuntimeError, /must run outside a database transaction/)
    end
  end

  context "with two concurrent grants", transaction: false do
    let!(:instances) { Array.new(2) { X402::Settlement.find(settlement.id) } }

    before do
      allow(X402::Wallets::ResolveService).to receive(:call!).and_wrap_original do |original, **kwargs|
        sleep(0.05)
        original.call(**kwargs)
      end
    end

    it "grants once" do
      results = Concurrent::Array.new
      instances.map { |instance| Thread.new { results << described_class.call(settlement: instance) } }.each(&:join)

      expect(results).to all(be_success)
      expect(WalletTransaction.count).to eq(1)
      expect(results.map { |r| r.settlement.wallet_transaction_id }.uniq).to eq([settlement.reload.wallet_transaction_id])
    end
  end

  context "with an invoice drawing on the wallet", transaction: false do
    subject(:outcomes) do
      invoice_id = invoice.id
      settlement_id = settlement.id
      invoice_side = race { Credits::AppliedPrepaidCreditsService.call(invoice: Invoice.find(invoice_id)) }
      raise "the invoice never locked the wallet" unless wallet_held.wait(5)

      grant_side = race { described_class.call(settlement: X402::Settlement.find(settlement_id)) }
      [invoice_side, grant_side].map { |side| side.join(15) ? side.value : :timed_out }
    end

    let(:customer) { create(:customer, organization:, currency: "USD", external_id: "x402_#{payer_address}", x402_agent_address: payer_address) }
    let(:ended_subscription) { create(:subscription, :terminated, customer:, plan:, external_id: "x402_#{payer_address}_agent_api") }
    let(:wallet) do
      create(:wallet, :with_inbound_transaction, customer:, code: "agent_credits", currency: "USD", rate_amount: "0.001", balance_cents: 1000, credits_balance: 10_000, x402_enabled: true)
    end
    let(:invoice) { create(:invoice, customer:, currency: "USD", total_amount_cents: 100, taxes_amount_cents: 0) }
    let(:wallet_held) { Concurrent::CountDownLatch.new }

    before do
      create(:charge_fee, invoice:, subscription: ended_subscription, amount_cents: 100, precise_amount_cents: 100, taxes_precise_amount_cents: 0)
      wallet
      wallet_held
      allow(Customers::RefreshWalletsService).to receive(:call).and_wrap_original do |original, **kwargs|
        wallet_held.count_down
        await_a_blocked_session
        original.call(**kwargs)
      end
    end

    def race(&block)
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection(&block)
      rescue => e
        e
      end
    end

    def await_a_blocked_session
      50.times do
        break if ActiveRecord::Base.with_connection { |connection| connection.select_value(<<~SQL) }
          SELECT EXISTS (SELECT 1 FROM pg_locks WHERE NOT granted AND pg_backend_pid() = ANY(pg_blocking_pids(pid)))
        SQL

        sleep(0.1)
      end
    end

    it "settles the invoice" do
      expect(outcomes.first).to be_success
    end

    it "grants the purchase" do
      expect(outcomes.last).to be_success
    end

    it "credits the wallet once" do
      outcomes

      expect(wallet.reload.credits_balance).to eq(BigDecimal("19000"))
    end
  end
end
