# frozen_string_literal: true

require "rails_helper"

describe "Invoice usage when a wallet expires", transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: []) }
  let(:billing_entity) { create(:billing_entity, organization:, invoice_grace_period: 0) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
  let(:billable_metric) { create(:billable_metric, organization:, field_name: "total", aggregation_type: "sum_agg") }
  let(:invoice_usage_on_expiration) { true }

  before do
    create(:charge, plan:, billable_metric:, charge_model: "standard", properties: {"amount" => "1"})
  end

  def subscribe_with_expiring_wallet
    subscription = create_subscription(
      {external_customer_id: customer.external_id, external_id: "sub_expiring_wallet", plan_code: plan.code},
      as: :model
    )

    wallet = create_wallet({
      external_customer_id: customer.external_id,
      rate_amount: "1",
      name: "Two weeks of free credits",
      currency: "EUR",
      granted_credits: "10",
      expiration_at: DateTime.new(2026, 3, 15).iso8601,
      invoice_usage_on_expiration:
    }, as: :model)

    [subscription, wallet]
  end

  it "applies the wallet credits to the usage consumed before expiration" do
    subscription, wallet = travel_to(DateTime.new(2026, 3, 1)) { subscribe_with_expiring_wallet }

    travel_to(DateTime.new(2026, 3, 5)) { ingest_event(subscription, billable_metric, 4) }

    travel_to(DateTime.new(2026, 3, 15, 1)) do
      clock_job { Clock::TerminateWalletsJob.perform_later }

      progressive_invoice = customer.invoices.progressive_billing.sole
      expect(progressive_invoice).to have_attributes(
        status: "finalized",
        progressive_billing_trigger: "wallet_expiration",
        fees_amount_cents: 4_00,
        prepaid_credit_amount_cents: 4_00,
        total_amount_cents: 0
      )
      expect(progressive_invoice.applied_wallet_expiration.wallet).to eq(wallet)
      expect(wallet.reload).to have_attributes(status: "terminated", balance_cents: 6_00)
    end

    travel_to(DateTime.new(2026, 3, 20)) { ingest_event(subscription, billable_metric, 3) }

    travel_to(DateTime.new(2026, 4, 1)) do
      perform_billing

      expect(customer.invoices.subscription.sole).to have_attributes(
        status: "finalized",
        fees_amount_cents: 7_00,
        progressive_billing_credit_amount_cents: 4_00,
        prepaid_credit_amount_cents: 0,
        total_amount_cents: 3_00
      )
    end
  end

  context "when the wallet does not invoice its usage on expiration" do
    let(:invoice_usage_on_expiration) { false }

    it "terminates the wallet with its credits unused" do
      subscription, wallet = travel_to(DateTime.new(2026, 3, 1)) { subscribe_with_expiring_wallet }

      travel_to(DateTime.new(2026, 3, 5)) { ingest_event(subscription, billable_metric, 4) }

      travel_to(DateTime.new(2026, 3, 15, 1)) do
        clock_job { Clock::TerminateWalletsJob.perform_later }

        expect(customer.invoices).to be_empty
        expect(wallet.reload).to have_attributes(status: "terminated", balance_cents: 10_00)
      end
    end
  end
end
