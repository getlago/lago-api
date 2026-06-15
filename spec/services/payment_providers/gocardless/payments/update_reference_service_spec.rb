# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Gocardless::Payments::UpdateReferenceService do
  subject(:service_result) { described_class.call(payment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:, status: :finalized, number: "INV-2026-001") }
  let(:payment_provider) { create(:gocardless_provider, organization:) }
  let(:gocardless_customer) { create(:gocardless_customer, customer:, payment_provider:) }
  let(:payment) do
    create(
      :payment,
      payable: invoice,
      payment_provider:,
      payment_provider_customer: gocardless_customer,
      organization:,
      customer:,
      provider_payment_id: "PM_abc",
      payable_payment_status: :succeeded,
      amount_cents: 25_00,
      amount_currency: "EUR"
    )
  end

  let(:gocardless_client) { instance_double(GoCardlessPro::Client) }
  let(:gocardless_payments_service) { instance_double(GoCardlessPro::Services::PaymentsService) }

  before do
    allow(GoCardlessPro::Client).to receive(:new).and_return(gocardless_client)
    allow(gocardless_client).to receive(:payments).and_return(gocardless_payments_service)
    allow(gocardless_payments_service).to receive(:update)
  end

  it "calls GoCardless with the finalized invoice number in metadata" do
    service_result

    expect(gocardless_payments_service).to have_received(:update).with(
      "PM_abc",
      params: {metadata: {lago_invoice_number: "INV-2026-001"}}
    )
  end

  it "returns success with the payment" do
    expect(service_result).to be_success
    expect(service_result.payment).to eq(payment)
  end

  context "when the payment has no provider_payment_id" do
    before { payment.update!(provider_payment_id: nil) }

    it "skips the GoCardless call" do
      service_result

      expect(gocardless_payments_service).not_to have_received(:update)
    end
  end

  context "when the payable is not an Invoice" do
    let(:payment_request) { create(:payment_request, customer:, organization:) }
    let(:payment) do
      create(:payment, payable: payment_request, payment_provider:, payment_provider_customer: gocardless_customer,
        organization:, customer:, provider_payment_id: "PM_abc", payable_payment_status: :succeeded)
    end

    it "skips the GoCardless call" do
      service_result

      expect(gocardless_payments_service).not_to have_received(:update)
    end
  end

  context "when the invoice has no number yet" do
    before do
      invoice.update_column(:number, "") # rubocop:disable Rails/SkipsModelValidations
    end

    it "skips the GoCardless call" do
      service_result

      expect(gocardless_payments_service).not_to have_received(:update)
    end
  end

  context "when GoCardless returns an error" do
    before do
      allow(gocardless_payments_service).to receive(:update)
        .and_raise(GoCardlessPro::Error.new("code" => "internal_error", "message" => "Boom"))
    end

    it "logs a warning and returns success" do
      allow(Rails.logger).to receive(:warn)

      expect(service_result).to be_success
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_matching(/failed to update GoCardless payment PM_abc/))
    end

    it "does not raise" do
      expect { service_result }.not_to raise_error
    end
  end
end
