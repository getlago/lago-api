# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::Balance::AllocateOngoingUsageByWalletsService do
  subject(:result) do
    described_class.call(
      customer:,
      wallets:,
      current_usage_fees:,
      draft_invoices_fees:,
      progressive_billing_fees:,
      pay_in_advance_fees:
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }

  let(:draft_invoices_fees) { [] }
  let(:progressive_billing_fees) { [] }
  let(:pay_in_advance_fees) { [] }

  # Wallet B (free, consumed first) and Wallet A (paid), as in the ticket worked example.
  let(:wallet_b) { create(:wallet, customer:, organization:, balance_cents: 50, priority: 1) }
  let(:wallet_a) { create(:wallet, customer:, organization:, balance_cents: 150, priority: 2) }
  let(:wallets) { [wallet_b, wallet_a] }

  def usage_fee(amount_cents:, charge: create(:standard_charge, organization:), currency: "EUR")
    create(:charge_fee, charge:, subscription:, organization:, invoice:,
      amount_cents:, taxes_amount_cents: 0, amount_currency: currency)
  end

  describe "#call" do
    context "with a single fee that overflows the first wallet" do
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      it "cascades the overflow onto the next wallet in priority order" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 30})
      end
    end

    context "when the first wallet has an active threshold-based recurring rule" do
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      before { create(:recurring_transaction_rule, wallet: wallet_b, organization:, trigger: :threshold) }

      it "absorbs everything on the threshold wallet and does not cascade" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 80, wallet_a => 0})
      end
    end

    context "when both wallets have an active threshold-based recurring rule" do
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      before do
        create(:recurring_transaction_rule, wallet: wallet_b, organization:, trigger: :threshold)
        create(:recurring_transaction_rule, wallet: wallet_a, organization:, trigger: :threshold)
      end

      it "lets the highest-priority threshold wallet absorb everything and does not cascade" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 80, wallet_a => 0})
      end
    end

    context "when the threshold rule is not active" do
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      before { create(:recurring_transaction_rule, wallet: wallet_b, organization:, trigger: :threshold, status: :terminated) }

      it "cascades as if there were no threshold rule" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 30})
      end
    end

    context "when a wallet has an active non-threshold (interval) recurring rule" do
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      before { create(:recurring_transaction_rule, wallet: wallet_b, organization:, trigger: :interval) }

      it "cascades like a normal wallet instead of absorbing everything" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 30})
      end
    end

    context "when a middle-priority wallet has an active threshold-based recurring rule" do
      let(:w1) { create(:wallet, customer:, organization:, balance_cents: 50, priority: 1) }
      let(:w2) { create(:wallet, customer:, organization:, balance_cents: 50, priority: 2) }
      let(:w3) { create(:wallet, customer:, organization:, balance_cents: 50, priority: 3) }
      let(:wallets) { [w1, w2, w3] }
      let(:current_usage_fees) { [usage_fee(amount_cents: 200)] }

      before { create(:recurring_transaction_rule, wallet: w2, organization:, trigger: :threshold) }

      it "fills the higher-priority wallet, then the threshold wallet absorbs the rest and stops the cascade" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({w1 => 50, w2 => 150, w3 => 0})
      end
    end

    context "with a single wallet" do
      let(:wallets) { [wallet_a] }
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      it "allocates the full usage to that wallet" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_a => 80})
      end
    end

    context "with a single non-threshold wallet whose usage exceeds its balance" do
      let(:wallets) { [wallet_b] }
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      it "lets the lone wallet absorb the overflow and go negative" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 80})
      end
    end

    context "when usage exceeds the sum of all wallet balances and no threshold rule exists" do
      let(:current_usage_fees) { [usage_fee(amount_cents: 250)] }

      it "fills each wallet then lets the last one absorb the overflow and go negative" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 200})
      end
    end

    context "with a pay-in-advance offset reducing the net usage" do
      let(:charge) { create(:standard_charge, organization:, pay_in_advance: true) }
      let(:usage) { usage_fee(amount_cents: 80, charge:) }
      let(:billed) { usage_fee(amount_cents: 30, charge:) }
      let(:current_usage_fees) { [usage] }
      let(:pay_in_advance_fees) { [billed] }

      it "nets the already-billed amount before cascading" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 0})
      end
    end

    context "with a progressive-billing offset reducing the net usage" do
      let(:charge) { create(:standard_charge, organization:) }
      let(:usage) { usage_fee(amount_cents: 80, charge:) }
      # Already progressively billed for the same charge, so it nets against the usage key.
      let(:billed) do
        create(:charge_fee, charge:, subscription:, organization:, invoice:,
          amount_cents: 30, taxes_amount_cents: 0, precise_coupons_amount_cents: 0, amount_currency: "EUR")
      end
      let(:current_usage_fees) { [usage] }
      let(:progressive_billing_fees) { [billed] }

      it "nets the progressively-billed amount before cascading" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 0})
      end
    end

    context "with a draft invoice fee adding to the net usage" do
      let(:charge) { create(:standard_charge, organization:) }
      let(:current_usage_fees) { [usage_fee(amount_cents: 40, charge:)] }
      let(:draft_invoices_fees) { [usage_fee(amount_cents: 40, charge:)] }

      it "sums usage and draft amounts before cascading" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 30})
      end
    end

    context "with wallet billable-metric targeting" do
      let(:billable_metric1) { create(:billable_metric, organization:) }
      let(:billable_metric2) { create(:billable_metric, organization:) }
      let(:charge1) { create(:standard_charge, organization:, billable_metric: billable_metric1) }
      let(:charge2) { create(:standard_charge, organization:, billable_metric: billable_metric2) }

      let(:wallet_b) { create(:wallet, customer:, organization:, balance_cents: 1000, priority: 1) }
      let(:wallet_a) { create(:wallet, customer:, organization:, balance_cents: 2000, priority: 2) }

      let(:current_usage_fees) { [usage_fee(amount_cents: 600, charge: charge1), usage_fee(amount_cents: 500, charge: charge2)] }

      before { create(:wallet_target, wallet: wallet_b, billable_metric: billable_metric1, organization:) }

      it "routes targeted fees to the targeting wallet and the rest to the unrestricted wallet" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 600, wallet_a => 500})
      end
    end

    context "with wallet fee-type restriction (allowed_fee_types)" do
      # wallet_b only accepts subscription fees, so the charge usage cascades past it to wallet_a.
      let(:wallet_b) { create(:wallet, customer:, organization:, balance_cents: 1000, priority: 1, allowed_fee_types: %w[subscription]) }
      let(:wallet_a) { create(:wallet, customer:, organization:, balance_cents: 2000, priority: 2, allowed_fee_types: %w[charge]) }
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      it "only allocates a fee to wallets whose allowed_fee_types include its type" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 0, wallet_a => 80})
      end
    end

    context "when a wallet currency does not match the fee currency" do
      let(:wallet_b) { create(:wallet, customer:, organization:, currency: "USD", balance_cents: 1000, priority: 1) }
      let(:wallet_a) { create(:wallet, customer:, organization:, currency: "EUR", balance_cents: 1000, priority: 2) }
      let(:current_usage_fees) { [usage_fee(amount_cents: 80, currency: "EUR")] }

      it "only allocates to wallets matching the fee currency" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 0, wallet_a => 80})
      end
    end

    context "with a zero-balance non-threshold wallet in the middle of the cascade" do
      let(:w1) { create(:wallet, customer:, organization:, balance_cents: 0, priority: 1) }
      let(:w2) { create(:wallet, customer:, organization:, balance_cents: 50, priority: 2) }
      let(:w3) { create(:wallet, customer:, organization:, balance_cents: 50, priority: 3) }
      let(:wallets) { [w1, w2, w3] }
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      it "skips the depleted wallet instead of forcing it negative" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({w1 => 0, w2 => 50, w3 => 30})
      end
    end

    context "with two fees on different metrics competing for the same wallets" do
      let(:current_usage_fees) do
        [usage_fee(amount_cents: 40, charge: create(:standard_charge, organization:)),
          usage_fee(amount_cents: 40, charge: create(:standard_charge, organization:))]
      end

      it "accounts for the first fee's allocation when the second fee reuses a wallet" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 30})
      end
    end

    context "with a subscription fee that has no charge" do
      let(:billable_metric) { create(:billable_metric, organization:) }
      let(:current_usage_fees) { [create(:fee, subscription:, organization:, invoice:, amount_cents: 80, taxes_amount_cents: 0, amount_currency: "EUR")] }

      before { create(:wallet_target, wallet: wallet_b, billable_metric:, organization:) }

      it "bypasses the metric-targeted wallet and lands on the unrestricted one" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 0, wallet_a => 80})
      end
    end

    context "when a fee is already fully covered by progressive billing (net usage of zero)" do
      let(:charge) { create(:standard_charge, organization:) }
      let(:current_usage_fees) { [usage_fee(amount_cents: 80, charge:)] }
      let(:progressive_billing_fees) do
        [create(:charge_fee, charge:, subscription:, organization:, invoice:,
          amount_cents: 80, taxes_amount_cents: 0, precise_coupons_amount_cents: 0, amount_currency: "EUR")]
      end

      it "drops the fully-billed fee key and allocates nothing" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 0, wallet_a => 0})
      end
    end

    context "when progressive billing exceeds one metric's usage" do
      let(:charge1) { create(:standard_charge, organization:) }
      let(:charge2) { create(:standard_charge, organization:) }
      let(:current_usage_fees) { [usage_fee(amount_cents: 80, charge: charge1), usage_fee(amount_cents: 100, charge: charge2)] }
      let(:progressive_billing_fees) do
        [create(:charge_fee, charge: charge2, subscription:, organization:, invoice:,
          amount_cents: 150, taxes_amount_cents: 0, precise_coupons_amount_cents: 0, amount_currency: "EUR")]
      end

      it "lets the over-billed key offset the other keys, like billing credits offset the invoice" do
        # net = 80 + (100 - 150) = 30, matching what billing would deduct from wallets
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 30, wallet_a => 0})
      end
    end

    context "when a fee targets a wallet code that matches no wallet" do
      around { |test| lago_premium! { test.run } }

      let(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"]) }
      let(:charge) { create(:standard_charge, organization:, accepts_target_wallet: true) }
      let(:current_usage_fees) do
        [create(:charge_fee, charge:, subscription:, organization:, invoice:, amount_cents: 80,
          taxes_amount_cents: 0, amount_currency: "EUR", grouped_by: {"target_wallet_code" => "missing-wallet"})]
      end

      it "allocates the fee to no wallet, matching billing where no wallet covers it" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 0, wallet_a => 0})
      end
    end

    context "when a fee targets a wallet whose balance is smaller than the fee" do
      around { |test| lago_premium! { test.run } }

      let(:organization) { create(:organization, premium_integrations: ["events_targeting_wallets"]) }
      let(:charge) { create(:standard_charge, organization:, accepts_target_wallet: true) }
      let(:wallet_b) { create(:wallet, customer:, organization:, code: "wallet-b", balance_cents: 50, priority: 1) }
      let(:current_usage_fees) do
        [create(:charge_fee, charge:, subscription:, organization:, invoice:, amount_cents: 80,
          taxes_amount_cents: 0, amount_currency: "EUR", grouped_by: {"target_wallet_code" => "wallet-b"})]
      end

      it "lets the targeted wallet absorb the full amount and go negative, never spilling onto other wallets" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 80, wallet_a => 0})
      end
    end

    context "when a wallet's in-memory balance is stale" do
      let(:current_usage_fees) { [usage_fee(amount_cents: 80)] }

      # Simulate a concurrent DecreaseService: the in-memory object is stale, the DB is authoritative.
      before { wallet_b.balance_cents = 999_99 }

      it "caps against the balance re-read from the database, not the stale value" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 50, wallet_a => 30})
      end
    end

    context "when there is no usage" do
      let(:current_usage_fees) { [] }

      it "allocates zero to every wallet" do
        expect(result).to be_success
        expect(result.wallet_allocations).to eq({wallet_b => 0, wallet_a => 0})
      end
    end
  end
end
