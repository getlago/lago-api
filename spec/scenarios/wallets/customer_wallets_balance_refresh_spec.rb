# frozen_string_literal: true

require "rails_helper"

describe "Use wallet's credits and recalculate balances", transaction: false do
  subject(:wallets) { refresh_service.wallets }

  let(:refresh_service) { Customers::RefreshWalletsService.call(customer:, include_generating_invoices:) }
  let(:include_generating_invoices) { true }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:, customer:, started_at: 2.years.ago) }

  let(:timestamp) { Time.current }

  let(:billable_metric) { create(:billable_metric, aggregation_type: "count_agg") }
  let(:billable_metric2) { create(:billable_metric, aggregation_type: "count_agg") }
  let(:billable_metric3) { create(:billable_metric, aggregation_type: "count_agg") }

  let(:first_charge) do
    create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: "10"})
  end

  let(:second_charge) do
    create(:standard_charge, plan: subscription.plan, billable_metric: billable_metric2, properties: {amount: "5"})
  end

  let(:wallet_attrs) do
    {
      customer:,
      balance_cents: 1000,
      ongoing_balance_cents: 0,
      ongoing_usage_balance_cents: 0,
      credits_balance: 10.0,
      credits_ongoing_balance: 0,
      credits_ongoing_usage_balance: 0,
      ready_to_be_refreshed: true
    }
  end

  let(:wallet) { create(:wallet, wallet_attrs) }
  let(:wallet2) { create(:wallet, wallet_attrs) }
  let(:wallet3) { create(:wallet, wallet_attrs.merge({name: "wallet 3"})) }
  let(:wallet_target) { create(:wallet_target, wallet:, billable_metric:) }
  let(:wallet_target2) { create(:wallet_target, wallet: wallet2, billable_metric: billable_metric2) }
  let(:wallet_target3) { create(:wallet_target, wallet: wallet3, billable_metric: billable_metric3) }

  let(:events) do
    create_list(
      :event, 3,
      organization:,
      subscription:,
      customer:,
      code: billable_metric.code,
      timestamp:
    ).push(
      create(
        :event,
        organization:,
        subscription:,
        customer:,
        code: billable_metric2.code,
        timestamp:
      )
    ).push(
      create(
        :event,
        organization:,
        subscription:,
        customer:,
        code: billable_metric3.code,
        timestamp:
      )
    )
  end

  context "with multiple wallets with restrictions" do
    before do
      wallet
      wallet2
      wallet3
      wallet_target
      wallet_target2
      first_charge
      second_charge
      events
    end

    it "returns all active wallets" do
      expect(wallets).to match_array(customer.wallets.active)
    end

    ##
    # USAGE                        WALLETS (priority order)
    #
    # bm1: $30 ────$10───────────▶ ┌─────────────────────────┐
    #           │                  │ wallet ($10, bm1 only)  │ ongoing: $0
    #           │                  └─────────────────────────┘
    # bm2: $5 ─────$5───────┐      ┌─────────────────────────┐
    #           │           └────▶ │ wallet2 ($10, bm2 only) │ ongoing: $5
    #           │                  └─────────────────────────┘
    #           └─$20 overflow───▶ ┌─────────────────────────┐
    #                              │ wallet3 ($10, catch-all)│ ongoing: -$10
    #                              └─────────────────────────┘
    ##
    it "updates the correct ongoing balances for each wallet" do
      expect_wallet(wallet, ongoing_usage: 1000, credits_usage: 10, ongoing: 0, credits: 0)
      expect_wallet(wallet2, ongoing_usage: 500, credits_usage: 5, ongoing: 500, credits: 5)
      expect_wallet(wallet3, ongoing_usage: 2000, credits_usage: 20, ongoing: -1000, credits: -10)
    end

    context "when there is paid in advance charges" do
      let(:third_charge) do
        create(:standard_charge, :pay_in_advance,
          invoiceable: false,
          plan: subscription.plan,
          billable_metric: billable_metric3,
          properties: {amount: "9999"})
      end

      before do
        third_charge
      end

      ##
      # Same cascade as the parent scenario; bm3 usage is pay-in-advance, so it is
      # already billed and nets to 0 -- it reaches no wallet.
      #
      # bm1: $30 ── $10 ▶ wallet ($10, bm1 only)    ongoing: $0
      #          └─ $20 ▶ wallet3 ($10, catch-all)  ongoing: -$10
      # bm2: $5 ──── $5 ▶ wallet2 ($10, bm2 only)   ongoing: $5
      # bm3: paid in advance ──▶ nets to $0
      ##
      it "updates the correct ongoing balances for each wallet" do
        expect_wallet(wallet, ongoing_usage: 1000, credits_usage: 10, ongoing: 0, credits: 0)
        expect_wallet(wallet2, ongoing_usage: 500, credits_usage: 5, ongoing: 500, credits: 5)
        expect_wallet(wallet3, ongoing_usage: 2000, credits_usage: 20, ongoing: -1000, credits: -10)
      end
    end

    # PROGRESSIVE BILLING
    context "when there is a progressive billing invoice" do
      let(:billable_metric3) { create(:billable_metric, aggregation_type: "count_agg") }
      let(:invoice_type) { :progressive_billing }
      let(:charges_to_datetime) { timestamp + 1.week }
      let(:charges_from_datetime) { timestamp - 1.week }

      let(:invoice_subscription) do
        create(:invoice_subscription,
          subscription:,
          charges_from_datetime:,
          charges_to_datetime:)
      end

      let(:invoice) { invoice_subscription.invoice }

      let(:fee) do
        create(
          :charge_fee,
          charge: second_charge,
          subscription:,
          precise_coupons_amount_cents: 10,
          invoice:,
          amount_cents: 100,
          taxes_amount_cents: 10
        )
      end
      let(:third_charge) do
        create(:standard_charge, plan: subscription.plan, billable_metric: billable_metric3, properties: {amount: "33"})
      end
      let(:fee2) do
        create(
          :charge_fee,
          charge: third_charge,
          subscription:,
          precise_coupons_amount_cents: 10,
          invoice:,
          amount_cents: 100,
          taxes_amount_cents: 10
        )
      end

      before do
        fee
        fee2
        invoice.update!(invoice_type:, fees_amount_cents: 210, total_amount_cents: 210)
      end

      ##
      # The progressive billing invoice nets $1 out of bm2 ($1 + $0.10 tax - $0.10 coupon)
      # and $1 out of bm3, before the cascade runs.
      #
      # bm1: $30 ──────── $10 ▶ wallet ($10, bm1 only)    ongoing: $0
      #                └─ $20 ▶ wallet3 (overflow)
      # bm2: $5 - $1 ────── $4 ▶ wallet2 ($10, bm2 only)  ongoing: $6
      # bm3: $33 - $1 ──── $32 ▶ wallet3 (only match)
      #
      # wallet3 ($10, catch-all): $20 + $32 = $52 consumed, ongoing: -$42
      ##
      it "updates wallet ongoing balances including progressive billing invoice" do
        expect_wallet(wallet, ongoing_usage: 1000, credits_usage: 10, ongoing: 0, credits: 0)
        expect_wallet(wallet2, ongoing_usage: 400, credits_usage: 4, ongoing: 600, credits: 6)
        expect_wallet(wallet3, ongoing_usage: 5200, credits_usage: 52, ongoing: -4200, credits: -42)
      end
    end

    context "when there is a draft invoice" do
      let(:draft_invoice) do
        create(
          :invoice,
          status: :draft,
          issuing_date: DateTime.now,
          customer:,
          organization: customer.organization
        )
      end

      let(:fee) do
        create(
          :charge_fee,
          charge: second_charge,
          subscription:,
          precise_coupons_amount_cents: 70, # simulate progressive billing
          invoice: draft_invoice,
          amount_cents: 100,
          taxes_amount_cents: 10
        )
      end

      before do
        fee
        draft_invoice.update!(fees_amount_cents: 110, total_amount_cents: 110)
      end

      ##
      # The draft invoice adds $0.40 to bm2 ($1 + $0.10 tax - $0.70 already paid)
      # before the cascade runs. bm3 has no charge here, so its event prices nothing.
      #
      # bm1: $30 ────────── $10 ▶ wallet ($10, bm1 only)    ongoing: $0
      #                  └─ $20 ▶ wallet3 ($10, catch-all)  ongoing: -$10
      # bm2: $5 + $0.40 ── $5.40 ▶ wallet2 ($10, bm2 only)  ongoing: $4.60
      ##
      it "updates wallet ongoing balances including progressive billing invoice" do
        expect_wallet(wallet, ongoing_usage: 1000, credits_usage: 10, ongoing: 0, credits: 0)
        expect_wallet(wallet2, ongoing_usage: 540, credits_usage: 5.4, ongoing: 460, credits: 4.6)
        expect_wallet(wallet3, ongoing_usage: 2000, credits_usage: 20, ongoing: -1000, credits: -10)
      end
    end
  end

  def expect_wallet(wallet, ongoing_usage:, credits_usage:, ongoing:, credits:)
    w = wallets.find(wallet.id)
    expect(w.ongoing_usage_balance_cents).to eq ongoing_usage
    expect(w.credits_ongoing_usage_balance).to eq credits_usage
    expect(w.ongoing_balance_cents).to eq ongoing
    expect(w.credits_ongoing_balance).to eq credits
  end
end
