# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CreateJob do
  let(:invoice) { create(:invoice) }
  let(:payment_provider) { "stripe" }

  it "calls the stripe create service" do
    allow(Invoices::Payments::CreateService).to receive(:call!)
      .with(invoice:, payment_provider:, payment_method_params: {})
      .and_return(Invoices::Payments::CreateService::Result.new)

    described_class.perform_now(invoice:, payment_provider:, payment_method_params: {})

    expect(Invoices::Payments::CreateService).to have_received(:call!)
  end

  context "when the customer has no payment provider type and the organization has several providers" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, payment_provider: nil, payment_provider_code: nil) }
    let(:invoice) { create(:invoice, customer:, organization:, status: :finalized, total_amount_cents: 100) }

    before do
      create(:stripe_provider, code: "stripe_1", organization:)
      create(:stripe_provider, code: "stripe_2", organization:)
    end

    it "skips the payment without failing" do
      expect { described_class.perform_now(invoice:, payment_provider:) }
        .not_to have_enqueued_job(SendWebhookJob)

      expect(invoice.reload.payment_status).to eq("pending")
      expect(invoice.payment_attempts).to eq(0)
      expect(invoice.payments.count).to eq(0)
    end
  end
end
