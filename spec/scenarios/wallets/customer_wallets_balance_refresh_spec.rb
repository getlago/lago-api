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
    # wallet 1
    # 1000 - 3000(from events) = -2000
    # wallet 2
    # 1000 - 500(from event) = 500
    ##
    it "updates the correct ongoing balances for each wallet" do
      expect_wallet(wallet, ongoing_usage: 3000, credits_usage: 30, ongoing: -2000, credits: -20)
      expect_wallet(wallet2, ongoing_usage: 500, credits_usage: 5, ongoing: 500, credits: 5)
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

      it "updates the correct ongoing balances for each wallet" do
        expect_wallet(wallet, ongoing_usage: 3000, credits_usage: 30, ongoing: -2000, credits: -20)
        expect_wallet(wallet2, ongoing_usage: 500, credits_usage: 5, ongoing: 500, credits: 5)
        expect_wallet(wallet3, ongoing_usage: 0, credits_usage: 0, ongoing: 1000, credits: 10)
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
      # wallet 1
      # 1000 - 3000(from events) = -2000 #untouched
      # wallet 2
      # fee 2 is not taken into account because of the wallet restrictions
      # 1000 - 500(from event) - 100(from invoice) ( 100 + 10(tax) - 10(already paid) )
      # = 400 # progressive billing invoice
      ##
      it "updates wallet ongoing balances including progressive billing invoice" do
        expect_wallet(wallet, ongoing_usage: 3000, credits_usage: 30, ongoing: -2000, credits: -20)
        expect_wallet(wallet2, ongoing_usage: 400, credits_usage: 4, ongoing: 600, credits: 6)
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
      # wallet 1
      # 1000 - 3000(from events) = -2000 #untouched
      # wallet 2
      # 1000 - 500(from event) - 110(from draft invoice) + 70 (already paid)
      # = 540 # progressive billing invoice
      ##
      it "updates wallet ongoing balances including progressive billing invoice" do
        expect_wallet(wallet, ongoing_usage: 3000, credits_usage: 30, ongoing: -2000, credits: -20)
        expect_wallet(wallet2, ongoing_usage: 540, credits_usage: 5.4, ongoing: 460, credits: 4.6)
      end
    end
  end

  # ==========================================================================
  # Standard charge with pricing_group_keys, no filters
  # ==========================================================================
  context "with standard charge and pricing_group_keys without filters" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

    let(:charge) do
      create(:standard_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {amount: "10", pricing_group_keys: ["agent_name"]})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {agent_name: "bot_a"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {agent_name: "bot_a"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {agent_name: "bot_b"})
      ]
    end

    before do
      wallet
      charge
      events
    end

    ##
    # bot_a: 2 events × $10 = 2000 cents
    # bot_b: 1 event × $10 = 1000 cents
    # Total usage: 3000 cents
    # Wallet: balance 1000 - 3000 = -2000
    ##
    it "correctly calculates wallet balance skipping groupeing fees" do
      allow(::Invoices::CustomerUsageService).to receive(:call!).and_call_original

      expect_wallet(wallet, ongoing_usage: 3000, credits_usage: 30, ongoing: -2000, credits: -20)

      expect(::Invoices::CustomerUsageService).to have_received(:call!).with(
        hash_including(usage_filters: having_attributes(skip_grouping: true))
      )
    end
  end

  # ==========================================================================
  # Standard charge with filters, no groups
  # ==========================================================================
  context "with standard charge and filters without groups" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

    let(:bm_filter) do
      create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu])
    end

    let(:charge) do
      create(:standard_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {amount: "10"})
    end

    let(:cf) do
      create(:charge_filter, charge:, properties: {amount: "5"})
    end

    let(:cf_value) do
      create(:charge_filter_value, charge_filter: cf, billable_metric_filter: bm_filter, values: ["us"])
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {region: "us"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {region: "us"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {region: "eu"})
      ]
    end

    before do
      wallet
      bm_filter
      charge
      cf
      cf_value
      events
    end

    ##
    # US events (charge_filter, amount: $5): 2 × $5 = 1000 cents
    # EU events (default, amount: $10): 1 × $10 = 1000 cents
    # Total usage: 2000 cents
    # Wallet: balance 1000 - 2000 = -1000
    ##
    it "correctly calculates wallet balance with filtered fees" do
      expect_wallet(wallet, ongoing_usage: 2000, credits_usage: 20, ongoing: -1000, credits: -10)
    end
  end

  # ==========================================================================
  # Standard charge with both groups and filters
  # ==========================================================================
  context "with standard charge with groups and filters combined" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

    let(:bm_filter) do
      create(:billable_metric_filter, billable_metric:, key: "region", values: %w[us eu])
    end

    let(:charge) do
      create(:standard_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {amount: "10", pricing_group_keys: ["agent_name"]})
    end

    let(:cf) do
      create(:charge_filter, charge:, properties: {amount: "5", pricing_group_keys: ["agent_name"]})
    end

    let(:cf_value) do
      create(:charge_filter_value, charge_filter: cf, billable_metric_filter: bm_filter, values: ["us"])
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {region: "us", agent_name: "bot_a"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {region: "us", agent_name: "bot_a"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {region: "us", agent_name: "bot_b"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {region: "eu", agent_name: "bot_a"})
      ]
    end

    before do
      wallet
      bm_filter
      charge
      cf
      cf_value
      events
    end

    ##
    # US/bot_a (filter match, $5): 2 × $5 = 1000 cents
    # US/bot_b (filter match, $5): 1 × $5 = 500 cents
    # EU/bot_a (default, $10): 1 × $10 = 1000 cents
    # Total usage: 2500 cents
    # Wallet: balance 1000 - 2500 = -1500
    ##
    it "correctly calculates wallet balance with grouped and filtered fees" do
      allow(::Invoices::CustomerUsageService).to receive(:call!).and_call_original
      expect_wallet(wallet, ongoing_usage: 2500, credits_usage: 25, ongoing: -1500, credits: -15)
      expect(::Invoices::CustomerUsageService).to have_received(:call!).with(
        hash_including(usage_filters: having_attributes(skip_grouping: false))
      )
    end
  end

  # ==========================================================================
  # Graduated charge model
  # ==========================================================================
  context "with graduated charge" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

    let(:charge) do
      create(:graduated_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 3, per_unit_amount: "10", flat_amount: "0"},
            {from_value: 4, to_value: nil, per_unit_amount: "5", flat_amount: "0"}
          ]
        })
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      create_list(:event, 5, organization:, subscription:, customer:,
        code: billable_metric.code, timestamp:)
    end

    before do
      wallet
      charge
      events
    end

    ##
    # 5 events (count_agg → 5 units)
    # Tier 1 (0-3): 3 × $10 = 3000 cents
    # Tier 2 (4+):  2 × $5  = 1000 cents
    # Total usage: 4000 cents
    # Wallet: balance 1000 - 4000 = -3000
    ##
    it "correctly calculates wallet balance with graduated charge" do
      expect_wallet(wallet, ongoing_usage: 4000, credits_usage: 40, ongoing: -3000, credits: -30)
    end
  end

  # ==========================================================================
  # Package charge model
  # ==========================================================================
  context "with package charge" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

    let(:charge) do
      create(:package_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {amount: "30", package_size: 5, free_units: 2})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      create_list(:event, 7, organization:, subscription:, customer:,
        code: billable_metric.code, timestamp:)
    end

    before do
      wallet
      charge
      events
    end

    ##
    # 7 events (count_agg → 7 units)
    # free_units: 2 → billable units: 7 - 2 = 5
    # packages: ceil(5 / 5) = 1
    # Total usage: 1 × $30 = 3000 cents
    # Wallet: balance 1000 - 3000 = -2000
    ##
    it "correctly calculates wallet balance with package charge" do
      expect_wallet(wallet, ongoing_usage: 3000, credits_usage: 30, ongoing: -2000, credits: -20)
    end
  end

  # ==========================================================================
  # Percentage charge model (with sum_agg)
  # ==========================================================================
  context "with percentage charge" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }

    let(:charge) do
      create(:percentage_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {rate: "10", fixed_amount: "0"})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {value: "10"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {value: "20"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {value: "30"})
      ]
    end

    before do
      wallet
      charge
      events
    end

    ##
    # sum_agg: 10 + 20 + 30 = 60
    # rate: 10% → 10% × 60 = $6 = 600 cents
    # fixed_amount: $0
    # Total usage: 600 cents
    # Wallet: balance 1000 - 600 = 400
    ##
    it "correctly calculates wallet balance with percentage charge" do
      expect_wallet(wallet, ongoing_usage: 600, credits_usage: 6, ongoing: 400, credits: 4)
    end
  end

  # ==========================================================================
  # Volume charge model
  # ==========================================================================
  context "with volume charge" do
    let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

    let(:charge) do
      create(:volume_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {
          volume_ranges: [
            {from_value: 0, to_value: 5, per_unit_amount: "10", flat_amount: "0"},
            {from_value: 6, to_value: nil, per_unit_amount: "5", flat_amount: "100"}
          ]
        })
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      create_list(:event, 3, organization:, subscription:, customer:,
        code: billable_metric.code, timestamp:)
    end

    before do
      wallet
      charge
      events
    end

    ##
    # 3 events (count_agg → 3 units)
    # Volume falls in range 1 (0-5): 3 × $10 + $0 flat = 3000 cents
    # Total usage: 3000 cents
    # Wallet: balance 1000 - 3000 = -2000
    ##
    it "correctly calculates wallet balance with volume charge" do
      expect_wallet(wallet, ongoing_usage: 3000, credits_usage: 30, ongoing: -2000, credits: -20)
    end
  end

  # ==========================================================================
  # Graduated percentage charge model (with sum_agg)
  # ==========================================================================
  context "with graduated_percentage charge", :premium do
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }

    let(:charge) do
      create(:graduated_percentage_charge,
        plan: subscription.plan,
        billable_metric:,
        properties: {
          graduated_percentage_ranges: [
            {from_value: 0, to_value: 30, rate: "10", flat_amount: "0"},
            {from_value: 31, to_value: nil, rate: "5", flat_amount: "0"}
          ]
        })
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      Array.new(3) {
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {value: "20"})
      }
    end

    before do
      wallet
      charge
      events
    end

    ##
    # sum_agg: 20 + 20 + 20 = 60
    # Tier 1 (0-30): 10% × 30 = $3 = 300 cents
    # Tier 2 (31+):  5% × 30  = $1.5 = 150 cents
    # Total usage: 450 cents
    # Wallet: balance 1000 - 450 = 550
    ##
    it "correctly calculates wallet balance with graduated percentage charge" do
      expect_wallet(wallet, ongoing_usage: 450, credits_usage: 4.5, ongoing: 550, credits: 5.5)
    end
  end

  # ==========================================================================
  # All billable metric aggregation types with standard charge
  # ==========================================================================
  context "with sum_agg billable metric" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "amount") }

    let(:charge) do
      create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: "10"})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {amount: "3"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {amount: "7"})
      ]
    end

    before do
      wallet
      charge
      events
    end

    ##
    # sum_agg: 3 + 7 = 10 units
    # Standard: 10 × $10 = $100 = 10000 cents
    # Wallet: balance 1000 - 10000 = -9000
    ##
    it "correctly calculates wallet balance with sum aggregation" do
      expect_wallet(wallet, ongoing_usage: 10000, credits_usage: 100, ongoing: -9000, credits: -90)
    end
  end

  context "with max_agg billable metric" do
    let(:billable_metric) { create(:max_billable_metric, organization:, field_name: "value") }

    let(:charge) do
      create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: "100"})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {value: "5"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {value: "3"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {value: "8"})
      ]
    end

    before do
      wallet
      charge
      events
    end

    ##
    # max_agg: max(5, 3, 8) = 8 units
    # Standard: 8 × $100 = $800 = 80000 cents
    # Wallet: balance 1000 - 80000 = -79000
    ##
    it "correctly calculates wallet balance with max aggregation" do
      expect_wallet(wallet, ongoing_usage: 80000, credits_usage: 800, ongoing: -79000, credits: -790)
    end
  end

  context "with unique_count_agg billable metric" do
    let(:billable_metric) { create(:unique_count_billable_metric, organization:, field_name: "user_id") }

    let(:charge) do
      create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: "500"})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {user_id: "user_a"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {user_id: "user_b"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {user_id: "user_a"})
      ]
    end

    before do
      wallet
      charge
      events
    end

    ##
    # unique_count_agg: unique(user_a, user_b, user_a) = 2 units
    # Standard: 2 × $500 = $1000 = 100000 cents
    # Wallet: balance 1000 - 100000 = -99000
    ##
    it "correctly calculates wallet balance with unique count aggregation" do
      expect_wallet(wallet, ongoing_usage: 100000, credits_usage: 1000, ongoing: -99000, credits: -990)
    end
  end

  context "with latest_agg billable metric" do
    let(:billable_metric) { create(:latest_billable_metric, organization:, field_name: "seats") }

    let(:charge) do
      create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: "100"})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp: 2.hours.ago, properties: {seats: "5"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp: 1.hour.ago, properties: {seats: "3"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {seats: "8"})
      ]
    end

    before do
      wallet
      charge
      events
    end

    ##
    # latest_agg: latest value = 8 (most recent timestamp)
    # Standard: 8 × $100 = $800 = 80000 cents
    # Wallet: balance 1000 - 80000 = -79000
    ##
    it "correctly calculates wallet balance with latest aggregation" do
      expect_wallet(wallet, ongoing_usage: 80000, credits_usage: 800, ongoing: -79000, credits: -790)
    end
  end

  context "with weighted_sum_agg billable metric" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, organization:, field_name: "storage_gb") }

    let(:charge) do
      create(:standard_charge, plan: subscription.plan, billable_metric:, properties: {amount: "10"})
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      [
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp: 1.day.ago, properties: {storage_gb: "10"}),
        create(:event, organization:, subscription:, customer:,
          code: billable_metric.code, timestamp:, properties: {storage_gb: "20"})
      ]
    end

    before do
      wallet
      charge
      events
    end

    ##
    # weighted_sum_agg: time-weighted sum depends on billing period and event timestamps.
    # The exact value depends on the subscription period length and time-weighting logic.
    # We verify the wallet is refreshed and usage is non-zero.
    ##
    it "refreshes wallet balance with weighted sum aggregation" do
      w = wallets.find(wallet.id)
      expect(w.ongoing_usage_balance_cents).to be_positive
      expect(w.ongoing_balance_cents).to be < wallet.balance_cents
    end
  end

  # ==========================================================================
  # Complex case: all charge models combined on a single plan
  # ==========================================================================
  context "with all charge models combined on a single plan", :premium do
    let(:bm_standard) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:bm_graduated) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:bm_package) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:bm_percentage) { create(:sum_billable_metric, organization:, field_name: "value") }
    let(:bm_volume) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:bm_graduated_pct) { create(:sum_billable_metric, organization:, field_name: "value") }

    let(:standard_ch) do
      create(:standard_charge,
        plan: subscription.plan,
        billable_metric: bm_standard,
        properties: {amount: "10"})
    end

    let(:graduated_ch) do
      create(:graduated_charge,
        plan: subscription.plan,
        billable_metric: bm_graduated,
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 3, per_unit_amount: "10", flat_amount: "0"},
            {from_value: 4, to_value: nil, per_unit_amount: "5", flat_amount: "0"}
          ]
        })
    end

    let(:package_ch) do
      create(:package_charge,
        plan: subscription.plan,
        billable_metric: bm_package,
        properties: {amount: "30", package_size: 5, free_units: 2})
    end

    let(:percentage_ch) do
      create(:percentage_charge,
        plan: subscription.plan,
        billable_metric: bm_percentage,
        properties: {rate: "10", fixed_amount: "0"})
    end

    let(:volume_ch) do
      create(:volume_charge,
        plan: subscription.plan,
        billable_metric: bm_volume,
        properties: {
          volume_ranges: [
            {from_value: 0, to_value: 5, per_unit_amount: "10", flat_amount: "0"},
            {from_value: 6, to_value: nil, per_unit_amount: "5", flat_amount: "100"}
          ]
        })
    end

    let(:graduated_pct_ch) do
      create(:graduated_percentage_charge,
        plan: subscription.plan,
        billable_metric: bm_graduated_pct,
        properties: {
          graduated_percentage_ranges: [
            {from_value: 0, to_value: 30, rate: "10", flat_amount: "0"},
            {from_value: 31, to_value: nil, rate: "5", flat_amount: "0"}
          ]
        })
    end

    let(:wallet) { create(:wallet, wallet_attrs) }

    let(:events) do
      # Standard: 3 count events
      create_list(:event, 3, organization:, subscription:, customer:,
        code: bm_standard.code, timestamp:) +
        # Graduated: 5 count events
        create_list(:event, 5, organization:, subscription:, customer:,
          code: bm_graduated.code, timestamp:) +
        # Package: 7 count events
        create_list(:event, 7, organization:, subscription:, customer:,
          code: bm_package.code, timestamp:) +
        # Percentage: 3 sum events (value: 10, 20, 30 → sum=60)
        [
          create(:event, organization:, subscription:, customer:,
            code: bm_percentage.code, timestamp:, properties: {value: "10"}),
          create(:event, organization:, subscription:, customer:,
            code: bm_percentage.code, timestamp:, properties: {value: "20"}),
          create(:event, organization:, subscription:, customer:,
            code: bm_percentage.code, timestamp:, properties: {value: "30"})
        ] +
        # Volume: 3 count events
        create_list(:event, 3, organization:, subscription:, customer:,
          code: bm_volume.code, timestamp:) +
        # Graduated percentage: 3 sum events (value: 20 each → sum=60)
        Array.new(3) {
          create(:event, organization:, subscription:, customer:,
            code: bm_graduated_pct.code, timestamp:, properties: {value: "20"})
        }
    end

    before do
      wallet
      standard_ch
      graduated_ch
      package_ch
      percentage_ch
      volume_ch
      graduated_pct_ch
      events
    end

    ##
    # Standard:             3 events × $10                                    = 3000 cents
    # Graduated:            5 events → tier1: 3×$10=3000, tier2: 2×$5=1000   = 4000 cents
    # Package:              7 events, free=2, pkg_size=5 → 1 pkg × $30       = 3000 cents
    # Percentage:           sum=60, 10% × 60                                  = 600 cents
    # Volume:               3 events in range1 → 3 × $10                     = 3000 cents
    # Graduated percentage: sum=60, tier1(0-30): 10%×30=300, tier2(31+): 5%×30=150 = 450 cents
    # Total usage: 3000 + 4000 + 3000 + 600 + 3000 + 450 = 14050 cents
    # Wallet: balance 1000 - 14050 = -13050
    ##
    it "correctly calculates wallet balance across all charge models" do
      expect_wallet(wallet, ongoing_usage: 14050, credits_usage: 140.5, ongoing: -13050, credits: -130.5)
    end
  end

  # ==========================================================================
  # Complex case with all charge models + pricing_group_keys + filters
  # ==========================================================================
  context "with all charge models, pricing_group_keys and filters on a single plan" do
    let(:bm_standard) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:bm_graduated) { create(:billable_metric, organization:, aggregation_type: "count_agg") }
    let(:bm_volume) { create(:billable_metric, organization:, aggregation_type: "count_agg") }

    let(:bm_filter_region) do
      create(:billable_metric_filter, billable_metric: bm_standard, key: "region", values: %w[us eu])
    end

    # Standard charge with pricing_group_keys AND filter
    let(:standard_ch) do
      create(:standard_charge,
        plan: subscription.plan,
        billable_metric: bm_standard,
        properties: {amount: "10", pricing_group_keys: ["agent_name"]})
    end

    let(:standard_cf) do
      create(:charge_filter, charge: standard_ch, properties: {amount: "5", pricing_group_keys: ["agent_name"]})
    end

    let(:standard_cf_value) do
      create(:charge_filter_value, charge_filter: standard_cf, billable_metric_filter: bm_filter_region, values: ["us"])
    end

    # Graduated charge (no groups, no filters)
    let(:graduated_ch) do
      create(:graduated_charge,
        plan: subscription.plan,
        billable_metric: bm_graduated,
        properties: {
          graduated_ranges: [
            {from_value: 0, to_value: 3, per_unit_amount: "10", flat_amount: "0"},
            {from_value: 4, to_value: nil, per_unit_amount: "5", flat_amount: "0"}
          ]
        })
    end

    # Volume charge (no groups, no filters)
    let(:volume_ch) do
      create(:volume_charge,
        plan: subscription.plan,
        billable_metric: bm_volume,
        properties: {
          volume_ranges: [
            {from_value: 0, to_value: 5, per_unit_amount: "10", flat_amount: "0"},
            {from_value: 6, to_value: nil, per_unit_amount: "5", flat_amount: "100"}
          ]
        })
    end

    # Two wallets: one restricted to bm_standard, one unrestricted
    let(:restricted_wallet) { create(:wallet, wallet_attrs.merge(name: "restricted")) }
    let(:unrestricted_wallet) { create(:wallet, wallet_attrs.merge(name: "unrestricted")) }
    let(:wallet_target_standard) { create(:wallet_target, wallet: restricted_wallet, billable_metric: bm_standard) }

    let(:events) do
      [
        # Standard: US/bot_a × 2, US/bot_b × 1, EU/bot_a × 1
        create(:event, organization:, subscription:, customer:,
          code: bm_standard.code, timestamp:, properties: {region: "us", agent_name: "bot_a"}),
        create(:event, organization:, subscription:, customer:,
          code: bm_standard.code, timestamp:, properties: {region: "us", agent_name: "bot_a"}),
        create(:event, organization:, subscription:, customer:,
          code: bm_standard.code, timestamp:, properties: {region: "us", agent_name: "bot_b"}),
        create(:event, organization:, subscription:, customer:,
          code: bm_standard.code, timestamp:, properties: {region: "eu", agent_name: "bot_a"})
      ] +
        # Graduated: 5 events
        create_list(:event, 5, organization:, subscription:, customer:,
          code: bm_graduated.code, timestamp:) +
        # Volume: 3 events
        create_list(:event, 3, organization:, subscription:, customer:,
          code: bm_volume.code, timestamp:)
    end

    before do
      restricted_wallet
      unrestricted_wallet
      wallet_target_standard
      bm_filter_region
      standard_ch
      standard_cf
      standard_cf_value
      graduated_ch
      volume_ch
      events
    end

    ##
    # Standard fees:
    #   US/bot_a: 2 × $5 = 1000, US/bot_b: 1 × $5 = 500, EU/bot_a: 1 × $10 = 1000
    #   Total standard: 2500 cents
    # Graduated fees:
    #   5 events → tier1: 3×$10=3000, tier2: 2×$5=1000 = 4000 cents
    # Volume fees:
    #   3 events in range1 → 3 × $10 = 3000 cents
    #
    # restricted_wallet (targets bm_standard only): usage = 2500
    #   balance 1000 - 2500 = -1500
    # unrestricted_wallet: usage = graduated(4000) + volume(3000) = 7000
    #   balance 1000 - 7000 = -6000
    ##
    it "correctly distributes fees between restricted and unrestricted wallets" do
      expect_wallet(restricted_wallet, ongoing_usage: 2500, credits_usage: 25, ongoing: -1500, credits: -15)
      expect_wallet(unrestricted_wallet, ongoing_usage: 7000, credits_usage: 70, ongoing: -6000, credits: -60)
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
