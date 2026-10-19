# frozen_string_literal: true

require "rails_helper"

RSpec.describe Wallets::ExpireService, transaction: false do
  subject(:result) { described_class.call(wallet:) }

  let(:plan) { create(:plan) }
  let(:organization) { plan.organization }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, plan:, customer:, started_at: 1.week.ago) }
  let(:invoice_usage_on_expiration) { true }

  let(:wallet) do
    create(
      :wallet,
      :with_inbound_transaction,
      customer:,
      balance_cents: 1000,
      credits_balance: 10.0,
      expiration_at: 1.hour.ago,
      invoice_usage_on_expiration:
    )
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
      timestamp: 2.hours.ago
    )
  end

  before do
    wallet
    charge
    event
  end

  it "invoices the usage with the wallet credits before terminating the wallet" do
    expect(result).to be_success

    invoice = customer.invoices.progressive_billing.sole
    expect(invoice).to have_attributes(fees_amount_cents: 100, prepaid_credit_amount_cents: 100, total_amount_cents: 0)
    expect(wallet.reload).to have_attributes(status: "terminated", balance_cents: 900)
  end

  context "when the wallet does not invoice its usage on expiration" do
    let(:invoice_usage_on_expiration) { false }

    it "terminates the wallet without invoicing" do
      expect(result).to be_success

      expect(customer.invoices).to be_empty
      expect(wallet.reload).to have_attributes(status: "terminated", balance_cents: 1000)
    end
  end

  context "when the wallet is already terminated" do
    before { wallet.mark_as_terminated! }

    it "does not invoice the usage" do
      expect(result).to be_success

      expect(customer.invoices).to be_empty
    end
  end

  context "when a subscription is in another currency than the wallet" do
    let(:other_subscription) do
      create(:subscription, plan: create(:plan, organization:, amount_currency: "USD"), customer:)
    end

    before do
      other_subscription
      allow(Invoices::ProgressiveBilling::WalletTerminationService).to receive(:call).and_call_original
    end

    it "only invoices the subscriptions in the wallet currency" do
      result

      expect(Invoices::ProgressiveBilling::WalletTerminationService).to have_received(:call).once
      expect(Invoices::ProgressiveBilling::WalletTerminationService).to have_received(:call).with(wallet:, subscription:)
    end
  end

  context "when the usage was already invoiced for this wallet" do
    before do
      allow(Invoices::ProgressiveBilling::WalletTerminationService).to receive(:call)
        .and_return(BaseService::Result.new.fail_with_error!(Idempotency::IdempotencyError.new("already invoiced")))
    end

    it "terminates the wallet" do
      expect(result).to be_success

      expect(wallet.reload.status).to eq("terminated")
    end
  end

  context "when invoicing the usage fails" do
    before do
      allow(Invoices::ProgressiveBilling::WalletTerminationService).to receive(:call)
        .and_return(BaseService::Result.new.service_failure!(code: "error", message: "error"))
    end

    it "raises and keeps the wallet active" do
      expect { result }.to raise_error(BaseService::ServiceFailure)

      expect(wallet.reload.status).to eq("active")
    end
  end
end
