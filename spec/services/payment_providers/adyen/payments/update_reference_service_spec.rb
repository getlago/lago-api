# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Adyen::Payments::UpdateReferenceService do
  subject(:service_result) { described_class.call(payment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, status: :finalized, number: "INV-2026-001") }
  let(:payment_provider) { create(:adyen_provider, organization:) }
  let(:adyen_customer) { create(:adyen_customer, customer:, payment_provider:) }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider:,
      payment_provider_customer: adyen_customer,
      organization:,
      customer:,
      provider_payment_id: "psp_ref_123",
      payable_payment_status: :succeeded,
      amount_cents: 25_00,
      amount_currency: "EUR"
    )
  end

  it "logs that Adyen does not support reference updates and returns success" do
    allow(Rails.logger).to receive(:info)

    expect(service_result).to be_success
    expect(service_result.payment).to eq(payment)
    expect(Rails.logger).to have_received(:info)
      .with(a_string_matching(/Adyen does not support updating captured payment references/))
  end

  it "does not raise" do
    expect { service_result }.not_to raise_error
  end
end
