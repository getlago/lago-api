# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::PaystackService do
  let(:organization) { create(:organization) }
  let(:code) { "paystack_1" }
  let(:payment_provider) { create(:paystack_provider, organization:, code:) }
  let(:customer) { create(:customer, organization:, payment_provider: "paystack", payment_provider_code: code, email: "customer@example.com") }
  let(:paystack_customer) { create(:paystack_customer, customer:, organization:, payment_provider:) }
  let(:invoice) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 50_000,
      currency: "NGN",
      ready_for_payment_processing: true
    )
  end
  let(:paystack_payment) do
    PaymentProviders::PaystackProvider::PaystackPayment.new(
      id: "4099260516",
      status: "success",
      metadata: {payment_type: "one-time", lago_invoice_id: invoice.id},
      authorization: nil,
      reference: "lago-invoice-ref",
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
    subject(:result) do
      described_class.call(
        :update_payment_status,
        organization_id: organization.id,
        status: paystack_payment.status,
        paystack_payment:,
        amount_cents:
      )
    end

    let(:amount_cents) { nil }

    it "creates a one-time payment and marks the invoice succeeded" do
      expect(result).to be_success
      expect(result.payment).to have_attributes(
        provider_payment_id: "4099260516",
        status: "success",
        payable_payment_status: "succeeded",
        payable: invoice
      )
      expect(invoice.reload).to have_attributes(
        payment_status: "succeeded",
        ready_for_payment_processing: false,
        total_paid_amount_cents: 50_000
      )
    end

    context "when the payment is partial" do
      let(:amount_cents) { 20_000 }

      it "uses the provider-reported amount" do
        expect(result).to be_success
        expect(result.payment.amount_cents).to eq(20_000)
        expect(invoice.reload.total_paid_amount_cents).to eq(20_000)
      end
    end

    context "when the charge failed" do
      let(:paystack_payment) do
        PaymentProviders::PaystackProvider::PaystackPayment.new(
          id: "4099260516",
          status: "failed",
          metadata: {payment_type: "one-time", lago_invoice_id: invoice.id},
          authorization: nil,
          reference: "lago-invoice-ref",
          amount: 50_000,
          currency: "NGN",
          gateway_response: "Declined"
        )
      end

      it "marks the invoice failed" do
        expect(result).to be_success
        expect(result.payment.payable_payment_status).to eq("failed")
        expect(invoice.reload).to have_attributes(payment_status: "failed", ready_for_payment_processing: true)
      end
    end
  end

  describe "#generate_payment_url" do
    subject(:result) { described_class.call(:generate_payment_url, invoice, payment_intent) }

    let(:payment_intent) { create(:payment_intent, invoice:) }
    let(:client) { instance_double(PaymentProviders::Paystack::Client) }

    before do
      allow(PaymentProviders::Paystack::Client).to receive(:new).and_return(client)
      allow(client).to receive(:initialize_transaction).and_return(
        "data" => {"authorization_url" => "https://checkout.paystack.com/test"}
      )
    end

    it "initializes hosted checkout" do
      expect(result).to be_success
      expect(result.payment_url).to eq("https://checkout.paystack.com/test")
      expect(result.provider_session_id).to be_nil
      expect(client).to have_received(:initialize_transaction).with(
        hash_including(amount: 50_000, currency: "NGN", reference: "lago-invoice-#{payment_intent.id}")
      )
    end

    context "when currency is unsupported" do
      before { invoice.update!(currency: "EUR") }

      it "returns a validation failure without calling Paystack" do
        expect(result).not_to be_success
        expect(result.error.messages[:currency]).to eq(["unsupported_currency"])
        expect(client).not_to have_received(:initialize_transaction)
      end
    end
  end
end
