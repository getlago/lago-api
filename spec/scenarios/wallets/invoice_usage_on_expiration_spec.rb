# frozen_string_literal: true

require "rails_helper"

describe "Invoice usage when a wallet expires", :premium, transaction: false do
  let(:organization) do
    create(:organization, webhook_url: nil, email_settings: [], feature_flags: ["invoice_usage_on_wallet_expiration"])
  end
  let(:billing_entity) { create(:billing_entity, organization:, invoice_grace_period: 0) }
  let(:customer) { create(:customer, organization:, billing_entity:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
  let(:billable_metric) { create(:billable_metric, organization:, field_name: "total", aggregation_type: "sum_agg") }
  let(:invoice_usage_on_expiration) { true }

  before do
    create(:charge, plan:, billable_metric:, charge_model: "standard", properties: {"amount" => "1"})
  end

  def subscribe_with_expiring_wallet(**wallet_params)
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
      invoice_usage_on_expiration:,
      **wallet_params
    }, as: :model)

    [subscription, wallet]
  end

  it "applies the wallet credits to the usage consumed before expiration" do
    subscription, wallet = travel_to(DateTime.new(2026, 3, 1)) { subscribe_with_expiring_wallet }

    travel_to(DateTime.new(2026, 3, 5)) { ingest_event(subscription, billable_metric, 4) }
    travel_to(DateTime.new(2026, 3, 15, 0, 30)) { ingest_event(subscription, billable_metric, 2) }

    travel_to(DateTime.new(2026, 3, 15, 1)) do
      clock_job { Clock::TerminateWalletsJob.perform_later }

      progressive_invoice = customer.invoices.progressive_billing.sole
      expect(progressive_invoice).to have_attributes(
        status: "finalized",
        progressive_billing_trigger: "wallet_expiration",
        fees_amount_cents: 4_00, # the 2 units ingested after the expiration are left out
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
        fees_amount_cents: 9_00, # 4 units before the expiration + 2 after it, before the clock run + 3 on 20 Mar
        progressive_billing_credit_amount_cents: 4_00,
        prepaid_credit_amount_cents: 0,
        total_amount_cents: 5_00
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

  context "when the expiring wallet is limited to a billable metric and the customer has another wallet" do
    let(:other_billable_metric) do
      create(:billable_metric, organization:, field_name: "total", aggregation_type: "sum_agg")
    end

    before do
      create(:charge, plan:, billable_metric: other_billable_metric, charge_model: "standard", properties: {"amount" => "1"})
    end

    def subscribe_with_two_wallets
      subscription, expiring_wallet = subscribe_with_expiring_wallet(applies_to: {billable_metric_codes: [billable_metric.code]})

      other_wallet = create_wallet({
        external_customer_id: customer.external_id,
        rate_amount: "1",
        name: "Main wallet",
        currency: "EUR",
        granted_credits: "20",
        priority: 1
      }, as: :model)

      [subscription, expiring_wallet, other_wallet]
    end

    it "spends the expiring wallet on its billable metric, then the other wallet on the rest" do
      subscription, expiring_wallet, other_wallet = travel_to(DateTime.new(2026, 3, 1)) { subscribe_with_two_wallets }

      travel_to(DateTime.new(2026, 3, 5)) do
        ingest_event(subscription, billable_metric, 4)
        ingest_event(subscription, other_billable_metric, 3)
      end

      travel_to(DateTime.new(2026, 3, 15, 1)) do
        clock_job { Clock::TerminateWalletsJob.perform_later }

        expect(customer.invoices.progressive_billing.sole).to have_attributes(
          status: "finalized",
          fees_amount_cents: 7_00, # 4 units of the expiring wallet's metric + 3 of the other metric
          prepaid_credit_amount_cents: 7_00,
          total_amount_cents: 0
        )
        # The other wallet has the higher priority, but the expiring wallet pays first, for its metric only.
        expect(expiring_wallet.reload).to have_attributes(status: "terminated", balance_cents: 6_00) # 10 - 4
        expect(other_wallet.reload).to have_attributes(status: "active", balance_cents: 17_00) # 20 - 3
      end

      travel_to(DateTime.new(2026, 4, 1)) do
        perform_billing

        expect(customer.invoices.subscription.sole).to have_attributes(
          fees_amount_cents: 7_00,
          progressive_billing_credit_amount_cents: 7_00, # all of it was billed at the expiration
          total_amount_cents: 0
        )
        expect(other_wallet.reload.balance_cents).to eq(17_00)
      end
    end
  end
end
