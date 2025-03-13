# frozen_string_literal: true

require "rails_helper"

describe "Use wallet's credits and recalculate balances", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["progressive_billing"]) }
  let(:plan) { create(:plan, organization: organization, interval: "monthly", amount_cents: 31_00, pay_in_advance: false) }
  let(:billable_metric) { create(:billable_metric, organization: organization, field_name: "total", aggregation_type: "sum_agg") }
  let(:charge) { create(:charge, plan: plan, billable_metric: billable_metric, charge_model: "standard", properties: {"amount" => "1"}) }
  let(:usage_threshold) { create(:usage_threshold, plan: plan, amount_cents: 200_00) }
  let(:usage_threshold2) { create(:usage_threshold, plan: plan, amount_cents: 500_00) }
  let(:customer) { create(:customer, organization: organization) }

  around { |test| lago_premium!(&test) }

  def ingest_event(subscription, amount)
    create_event({
                   transaction_id: SecureRandom.uuid,
                   code: billable_metric.code,
                   external_subscription_id: subscription.external_id,
                   properties: {"total" => amount}
                 })
    perform_usage_update
  end

  context "when plan has usage_threshold" do
    it "recalculates wallet's balance" do
      # Create a wallet with 10$
      create_wallet({
        external_customer_id: customer.external_id,
        rate_amount: "1",
        name: "Wallet1",
        currency: "EUR",
        granted_credits: "10",
        invoice_requires_successful_payment: false # default
      })
      wallet = customer.reload.wallets.sole
      expect(wallet.credits_balance).to eq 10

      # create a subscription
      time_0 = DateTime.new(2022, 12, 1)
      travel_to time_0 do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code
          }
        )
      end
      subscription = customer.subscriptions.first

      # ingest events that would use all wallet balance
      travel_to time_0 + 5.days do
        ingest_event(subscription, 5)
        expect(Invoice.count).to eq(0)
        recalculate_wallet_balances
        wallet.reload
        byebug
        expect(wallet.credits_balance).to eq 5
      end

      travel_to time_0 + 15.days do
        ingest_event(subscription, 1000000)
        expect(Invoice.count).to eq(1)
        progressive_billing_invoice = subscription.invoices.first
        expect(progressive_billing_invoice.total_amount_cents).to eq(20000)
      end

      travel_to time_0 + 1.month do
        perform_billing
        expect(Invoice.count).to eq(2)
        recurring_invoice = subscription.invoices.order(:created_at).last
        expect(recurring_invoice.total_amount_cents).to eq(31_00 + 20_000)
        expect(recurring_invoice.fees_amount_cents).to eq(31_00 + 40_000)
        expect(recurring_invoice.progressive_billing_credit_amount_cents).to eq(20_000)
      end

    end
  end
end
