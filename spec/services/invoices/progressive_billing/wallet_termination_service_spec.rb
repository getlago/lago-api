# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::ProgressiveBilling::WalletTerminationService, transaction: false do
  subject(:result) { described_class.call(wallet:, subscription:, timestamp:) }

  let(:plan) { create(:plan) }
  let(:organization) { plan.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, plan:, customer:, started_at: timestamp - 1.week) }
  let(:timestamp) { Time.zone.parse(Date.current.strftime("%Y-%m-%d 10:00:00")) }

  let(:wallet) do
    create(:wallet, :with_inbound_transaction, customer:, balance_cents: 1000, credits_balance: 10.0)
  end

  let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: {amount: "1"}) }

  let(:event) do
    create(
      :event,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      properties: {billable_metric.field_name => 1},
      timestamp: timestamp - 1.hour
    )
  end

  before do
    wallet
    charge
    event
  end

  it "creates a progressive billing invoice paid with the wallet credits" do
    expect(result).to be_success
    expect(result.invoice).to have_attributes(
      customer:,
      status: "finalized",
      invoice_type: "progressive_billing",
      fees_amount_cents: 100,
      prepaid_credit_amount_cents: 100,
      total_amount_cents: 0,
      payment_status: "succeeded"
    )
    expect(result.invoice.invoice_subscriptions.map(&:subscription)).to eq([subscription])
    expect(result.invoice.applied_usage_thresholds).to be_empty
    expect(wallet.reload.balance_cents).to eq(900)
  end

  it "creates only one invoice per wallet and subscription" do
    expect(described_class.call(wallet:, subscription:, timestamp:)).to be_success

    create(
      :event,
      organization_id: organization.id,
      external_subscription_id: subscription.external_id,
      code: billable_metric.code,
      properties: {billable_metric.field_name => 1},
      timestamp: timestamp - 30.minutes
    )

    expect(result).not_to be_success
    expect(result.error).to be_a(Idempotency::IdempotencyError)
    expect(customer.invoices.progressive_billing.count).to eq(1)
  end

  it "does not invoice again the usage it already invoiced" do
    expect(described_class.call(wallet:, subscription:, timestamp:)).to be_success

    expect(result).to be_success
    expect(result.invoice).to be_nil
    expect(customer.invoices.progressive_billing.count).to eq(1)
  end

  context "without usage" do
    let(:event) { nil }

    it "does not create an invoice" do
      expect { result }.not_to change(Invoice, :count)

      expect(result).to be_success
      expect(result.invoice).to be_nil
      expect(wallet.reload.balance_cents).to eq(1000)
    end

    it "does not enqueue the invoice side effects" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
    end
  end

  context "when the usage was already progressively billed" do
    before do
      invoice = create(
        :invoice,
        :with_subscriptions,
        organization:,
        customer:,
        status: "finalized",
        invoice_type: :progressive_billing,
        fees_amount_cents: 100,
        subscriptions: [subscription],
        issuing_date: timestamp - 1.day
      )

      create(:charge_fee, charge:, invoice:, amount_cents: 100)
      invoice.invoice_subscriptions.first.update!(
        charges_from_datetime: invoice.issuing_date - 2.weeks,
        charges_to_datetime: invoice.issuing_date + 2.weeks,
        timestamp: invoice.issuing_date
      )
    end

    it "does not create an invoice" do
      expect { result }.not_to change(Invoice, :count)

      expect(result).to be_success
      expect(result.invoice).to be_nil
      expect(Credit.count).to eq(0)
    end
  end
end
