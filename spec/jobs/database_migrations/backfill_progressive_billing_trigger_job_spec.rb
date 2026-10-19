# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseMigrations::BackfillProgressiveBillingTriggerJob do
  subject(:perform_job) { described_class.perform_now }

  let(:threshold_invoice) { create(:invoice, :progressive_billing_invoice, progressive_billing_trigger: nil) }
  let(:wallet_invoice) { create(:invoice, invoice_type: :progressive_billing, progressive_billing_trigger: "wallet_expiration") }
  let(:subscription_invoice) { create(:invoice) }

  before do
    threshold_invoice
    wallet_invoice
    subscription_invoice
  end

  it "marks the invoices with applied usage thresholds as triggered by a usage threshold" do
    perform_job

    expect(threshold_invoice.reload.progressive_billing_trigger).to eq("usage_threshold")
    expect(wallet_invoice.reload.progressive_billing_trigger).to eq("wallet_expiration")
    expect(subscription_invoice.reload.progressive_billing_trigger).to be_nil
  end

  it "does not enqueue another batch when the walk is over" do
    expect { perform_job }.not_to have_enqueued_job(described_class)
  end

  context "when the batch is full" do
    before { stub_const("#{described_class}::BATCH_SIZE", 1) }

    it "chains to the next batch from the last invoice id" do
      expect { perform_job }.to have_enqueued_job(described_class).with(threshold_invoice.id)
    end
  end
end
