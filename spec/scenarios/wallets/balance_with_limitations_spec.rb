# frozen_string_literal: true

require "rails_helper"

describe "Wallet balance with limitations and draft invoices", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["progressive_billing"]) }
  let(:billing_entity) { create(:billing_entity, organization:, invoice_grace_period: 10) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 100, pay_in_advance: false) }
  let(:billable_metric1) { create(:billable_metric, organization:, field_name: "total", aggregation_type: "sum_agg") }
  let(:billable_metric2) { create(:billable_metric, organization:, field_name: "count", aggregation_type: "sum_agg") }
  let(:charge1) { create(:charge, plan:, billable_metric: billable_metric1, charge_model: "standard", properties: {"amount" => "1"}) }
  let(:charge2) { create(:charge, plan:, billable_metric: billable_metric2, charge_model: "standard", properties: {"amount" => "2"}) }
  let(:customer) { create(:customer, organization:, billing_entity:) }

  around { |test| lago_premium!(&test) }

  def ingest_event(subscription, billable_metric, amount)
    create_event({
      transaction_id: SecureRandom.uuid,
      code: billable_metric.code,
      external_subscription_id: subscription.external_id,
      properties: {billable_metric.field_name => amount}
    })
    perform_usage_update
  end

  def create_wallet_with_limitations(billable_metrics: [], allowed_fee_types: [])
    params = {
      external_customer_id: customer.external_id,
      rate_amount: "1",
      name: "Limited Wallet",
      currency: "EUR",
      granted_credits: "100",
      invoice_requires_successful_payment: false
    }

    if billable_metrics.any? || allowed_fee_types.any?
      params[:applies_to] = {}
      params[:applies_to][:billable_metric_codes] = billable_metrics.map(&:code) if billable_metrics.any?
      params[:applies_to][:fee_types] = allowed_fee_types if allowed_fee_types.any?
    end

    create_wallet(params, as: :model)
  end

  context "when wallet is limited to specific billable metrics" do
    before do
      charge1
      charge2
    end

    it "only includes matching fees from draft invoices in ongoing balance" do
      time_0 = DateTime.new(2022, 11, 30)
      wallet = nil

      travel_to time_0 do
        # Create a wallet limited to billable_metric1
        wallet = create_wallet_with_limitations(billable_metrics: [billable_metric1])
        expect(wallet.credits_balance).to eq 100
        expect(wallet.balance_cents).to eq 10_000
        expect(wallet.ongoing_balance_cents).to eq 10_000
        expect(wallet.ongoing_usage_balance_cents).to eq 0
      end

      # Create a subscription
      time_1 = time_0 + 1.day
      travel_to time_1 do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end
      subscription = customer.subscriptions.first

      # Ingest events for both metrics
      # metric1: 5 units * $1 = $5
      # metric2: 10 units * $2 = $20
      travel_to time_1 + 5.days do
        ingest_event(subscription, billable_metric1, 5)
        ingest_event(subscription, billable_metric2, 10)
        recalculate_wallet_balances
        wallet.reload
        # Only metric1 usage should be counted: $5
        expect(wallet.ongoing_usage_balance_cents).to eq 500
        expect(wallet.ongoing_balance_cents).to eq 9500
      end

      # Billing run creates a draft invoice
      # Draft invoice includes: subscription fee $1 + metric1 $5 + metric2 $20 = $26
      # But only metric1 charges should count for the wallet: $5
      time_2 = time_1 + 1.month
      travel_to time_2 do
        perform_billing
        expect(subscription.invoices.count).to eq(1)
        expect(subscription.invoices.first.status).to eq("draft")
        # Total invoice: 100 (sub) + 500 (metric1) + 2000 (metric2) = 2600
        expect(subscription.invoices.first.total_amount_cents).to eq(2600)

        recalculate_wallet_balances
        wallet.reload
        # Current usage should be 0 (no new events in this period)
        # Draft invoice contribution should only be metric1: $5 (500 cents)
        # The subscription fee and metric2 charges should NOT be counted
        expect(wallet.ongoing_usage_balance_cents).to eq 500
        expect(wallet.ongoing_balance_cents).to eq 9500
      end

      # Ingest more events in the new billing period
      travel_to time_2 + 5.days do
        ingest_event(subscription, billable_metric1, 3)
        ingest_event(subscription, billable_metric2, 7)
        recalculate_wallet_balances
        wallet.reload
        # Current usage: metric1 only = $3 (300 cents)
        # Draft invoice: metric1 only = $5 (500 cents)
        # Total ongoing usage: 800 cents
        expect(wallet.ongoing_usage_balance_cents).to eq 800
        expect(wallet.ongoing_balance_cents).to eq 9200
      end
    end
  end

  context "when wallet is limited to specific fee types" do
    before do
      charge1
      charge2
    end

    it "only includes matching fee types from draft invoices in ongoing balance" do
      time_0 = DateTime.new(2022, 11, 30)
      wallet = nil

      travel_to time_0 do
        # Create a wallet limited to subscription fees only
        wallet = create_wallet_with_limitations(allowed_fee_types: ["subscription"])
        expect(wallet.credits_balance).to eq 100
        expect(wallet.balance_cents).to eq 10_000
        expect(wallet.ongoing_balance_cents).to eq 10_000
        expect(wallet.ongoing_usage_balance_cents).to eq 0
      end

      # Create a subscription
      time_1 = time_0 + 1.day
      travel_to time_1 do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end
      subscription = customer.subscriptions.first

      # Ingest events for usage
      travel_to time_1 + 5.days do
        ingest_event(subscription, billable_metric1, 5)
        recalculate_wallet_balances
        wallet.reload
        # Current usage is from charge fees, not subscription fees
        # Since wallet is limited to subscription fees, current usage should not count
        expect(wallet.ongoing_usage_balance_cents).to eq 0
        expect(wallet.ongoing_balance_cents).to eq 10_000
      end

      # Billing run creates a draft invoice
      # Draft invoice includes: subscription fee $1 + metric1 $5 = $6
      # Only subscription fee should count for the wallet: $1
      time_2 = time_1 + 1.month
      travel_to time_2 do
        perform_billing
        expect(subscription.invoices.count).to eq(1)
        expect(subscription.invoices.first.status).to eq("draft")
        # Total invoice: 100 (sub) + 500 (metric1) = 600
        expect(subscription.invoices.first.total_amount_cents).to eq(600)

        recalculate_wallet_balances
        wallet.reload
        # Current usage: 0 (charge fees don't count for subscription-limited wallet)
        # Draft invoice contribution: subscription fee only = $1 (100 cents)
        expect(wallet.ongoing_usage_balance_cents).to eq 100
        expect(wallet.ongoing_balance_cents).to eq 9900
      end
    end
  end
end
