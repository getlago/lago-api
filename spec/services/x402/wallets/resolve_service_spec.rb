# frozen_string_literal: true

require "rails_helper"

describe X402::Wallets::ResolveService do
  subject(:result) { described_class.call(customer:, code: "agent_credits", shape:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "USD") }
  let(:shape) { {"name" => "Agent credits", "rate_amount" => "0.001", "currency" => "USD"} }

  before { allow(Wallets::CreateService).to receive(:call!).and_call_original }

  context "without a wallet for the code" do
    it "creates the wallet from the shape" do
      expect(result.wallet).to have_attributes(
        customer:,
        code: "agent_credits",
        name: "Agent credits",
        rate_amount: BigDecimal("0.001"),
        currency: "USD",
        status: "active",
        x402_enabled: true,
        expiration_at: nil,
        allowed_fee_types: [],
        paid_top_up_min_amount_cents: nil,
        paid_top_up_max_amount_cents: nil
      )
    end

    it "targets no billable metric" do
      expect(result.wallet.wallet_targets).to be_empty
    end

    it "carries no recurring transaction rule" do
      expect(result.wallet.recurring_transaction_rules).to be_empty
    end

    context "with top-up limits" do
      let(:shape) { {"name" => "Agent credits", "rate_amount" => "0.001", "currency" => "USD", "paid_top_up_min_amount_cents" => 100, "paid_top_up_max_amount_cents" => 100_000} }

      it "sets the limits" do
        expect(result.wallet).to have_attributes(paid_top_up_min_amount_cents: 100, paid_top_up_max_amount_cents: 100_000)
      end
    end

    context "with keys outside the shape" do
      let(:shape) { {"name" => "Agent credits", "rate_amount" => "0.001", "currency" => "USD", "expiration_at" => 1.day.from_now.iso8601, "applies_to" => {"fee_types" => ["charge"]}} }

      it "ignores them" do
        expect(result.wallet).to have_attributes(expiration_at: nil, allowed_fee_types: [])
      end
    end

    context "without a shape" do
      let(:shape) { nil }

      it "returns a validation failure" do
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end
  end

  context "with an active wallet for the code" do
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD", rate_amount: "0.5") }

    before { wallet }

    it "returns it" do
      expect(result.wallet).to eq(wallet)
    end

    it "ignores the shape" do
      result

      expect(Wallets::CreateService).not_to have_received(:call!)
    end
  end

  context "with a terminated wallet for the code" do
    let(:terminated_wallet) { create(:wallet, :terminated, customer:, code: "agent_credits", currency: "USD") }

    before { terminated_wallet }

    it "creates a fresh wallet" do
      expect(result.wallet).to have_attributes(code: "agent_credits", status: "active")
    end

    it "never returns the terminated wallet" do
      expect(result.wallet).not_to eq(terminated_wallet)
    end
  end

  context "with another customer's wallet for the code" do
    before { create(:wallet, customer: create(:customer, organization:), code: "agent_credits", currency: "USD") }

    it "creates the customer's own wallet" do
      expect(result.wallet.customer).to eq(customer)
    end
  end

  context "when a concurrent grant committed the wallet first" do
    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD") }

    before do
      wallet
      lookups = 0
      allow(customer).to receive(:wallets).and_wrap_original do |original|
        lookups += 1
        (lookups == 1) ? Wallet.none : original.call
      end
    end

    it "returns the wallet the other grant created" do
      expect(result.wallet).to eq(wallet)
    end

    context "when the insert loses the race on the unique index" do
      subject(:result) { ActiveRecord::Base.transaction { described_class.call(customer:, code: "agent_credits", shape:) } }

      before do
        allow(Wallets::CreateService).to receive(:call!) { wallet.dup.save!(validate: false) }
      end

      it "returns the wallet the other grant created" do
        expect(result.wallet).to eq(wallet)
      end
    end
  end

  context "when the wallet is terminated while the lookup waits", transaction: false do
    subject(:result) do
      ActiveRecord::Base.transaction { described_class.call(customer:, code: "agent_credits", shape:) }.tap { terminator.join(10) }
    end

    let(:wallet) { create(:wallet, customer:, code: "agent_credits", currency: "USD") }
    let(:terminated) { Concurrent::CountDownLatch.new }
    let(:terminator) do
      wallet_id = wallet.id
      latch = terminated
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ActiveRecord::Base.transaction do
            Wallets::TerminateService.call!(wallet: Wallet.find(wallet_id))
            latch.count_down
            await_a_blocked_session
          end
        end
      end
    end

    before do
      terminator
      raise "the wallet was never terminated" unless terminated.wait(5)
    end

    def await_a_blocked_session
      50.times do
        break if ActiveRecord::Base.with_connection { |connection| connection.select_value(<<~SQL) }
          SELECT EXISTS (SELECT 1 FROM pg_locks WHERE NOT granted AND pg_backend_pid() = ANY(pg_blocking_pids(pid)))
        SQL

        sleep(0.1)
      end
    end

    it "creates a fresh wallet" do
      expect(result.wallet).to have_attributes(code: "agent_credits", status: "active")
    end

    it "never returns the terminated wallet" do
      expect(result.wallet).not_to eq(wallet)
    end

    it "leaves the terminated wallet terminated" do
      result

      expect(wallet.reload).to be_terminated
    end
  end
end
