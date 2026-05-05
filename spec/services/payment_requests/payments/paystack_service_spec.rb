# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::PaystackService do
  subject(:service) { described_class.new(payment_request) }

  let(:organization) { create(:organization) }
  let(:code) { "paystack_1" }
  let(:payment_provider) { create(:paystack_provider, organization:, code:) }
  let(:customer) { create(:customer, organization:, payment_provider: "paystack", payment_provider_code: code, email: "customer@example.com") }
  let(:paystack_customer) { create(:paystack_customer, customer:, organization:, payment_provider:) }
  let(:invoice) { create(:invoice, organization:, customer:, currency: "NGN") }
  let(:payment_request) do
    create(
      :payment_request,
      organization:,
      customer:,
      invoices: [invoice],
      amount_cents: 50_000,
      amount_currency: "NGN"
    )
  end
  let(:paystack_payment) do
    PaymentProviders::PaystackProvider::PaystackPayment.new(
      id: "4099260516",
      status: "success",
      metadata: {payment_type: "one-time", lago_payable_id: payment_request.id, lago_payable_type: "PaymentRequest"},
      authorization: nil,
      reference: "lago-payment-request-ref",
      amount: 50_000,
      currency: "NGN",
      gateway_response: "Successful"
    )
  end

  before do
    payment_provider
    paystack_customer
  end

  describe "#update_payment_status" do
    it "creates a one-time payment and marks the payment request succeeded" do
      result = service.update_payment_status(
        organization_id: organization.id,
        status: paystack_payment.status,
        paystack_payment:
      )

      expect(result).to be_success
      expect(result.payment).to have_attributes(
        provider_payment_id: "4099260516",
        status: "success",
        payable_payment_status: "succeeded",
        payable: payment_request
      )
      expect(payment_request.reload).to be_payment_succeeded
    end
  end

  describe "#generate_payment_url" do
    let(:client) { instance_double(PaymentProviders::Paystack::Client) }

    before do
      allow(PaymentProviders::Paystack::Client).to receive(:new).and_return(client)
      allow(client).to receive(:initialize_transaction).and_return(
        "data" => {"authorization_url" => "https://checkout.paystack.com/test"}
      )
    end

    it "initializes hosted checkout" do
      result = service.generate_payment_url

      expect(result).to be_success
      expect(result.payment_url).to eq("https://checkout.paystack.com/test")
      expect(client).to have_received(:initialize_transaction).with(
        hash_including(amount: 50_000, currency: "NGN")
      )
    end

    context "when currency is unsupported" do
      before { payment_request.update!(amount_currency: "EUR") }

      it "returns a validation failure without calling Paystack" do
        result = service.generate_payment_url

        expect(result).not_to be_success
        expect(result.error.messages[:currency]).to eq(["unsupported_currency"])
        expect(client).not_to have_received(:initialize_transaction)
      end
    end
  end
end
