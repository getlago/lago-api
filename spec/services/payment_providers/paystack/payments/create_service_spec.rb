# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Paystack::Payments::CreateService do
  subject(:result) { described_class.call(payment:, reference:, metadata:) }

  let(:organization) { create(:organization) }
  let(:code) { "paystack_1" }
  let(:payment_provider) { create(:paystack_provider, organization:, code:) }
  let(:customer) { create(:customer, organization:, payment_provider: "paystack", payment_provider_code: code, email: "customer@example.com") }
  let(:paystack_customer) do
    create(
      :paystack_customer,
      organization:,
      customer:,
      payment_provider:,
      authorization_code: "AUTH_test",
      payment_method_id: "AUTH_test"
    )
  end
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
  let(:payment) do
    create(
      :payment,
      organization:,
      customer:,
      payable: invoice,
      payment_provider:,
      payment_provider_customer: paystack_customer,
      amount_cents: 50_000,
      amount_currency: invoice.currency,
      status: "pending",
      payable_payment_status: "pending"
    )
  end
  let(:reference) { "lago-payment-reference" }
  let(:metadata) { {lago_invoice_id: invoice.id} }
  let(:client) { instance_double(PaymentProviders::Paystack::Client) }

  before do
    allow(PaymentProviders::Paystack::Client).to receive(:new).and_return(client)
    allow(client).to receive(:charge_authorization).and_return(
      "message" => "Success",
      "data" => {
        "id" => 4_099_260_516,
        "status" => "success",
        "reference" => reference,
        "gateway_response" => "Successful",
        "authorization" => {
          "authorization_code" => "AUTH_new",
          "reusable" => true,
          "channel" => "card",
          "last4" => "4081",
          "brand" => "visa",
          "exp_month" => "12",
          "exp_year" => "2030"
        }
      }
    )
  end

  it "charges the saved authorization and updates the payment" do
    expect(result).to be_success
    expect(result.payment.reload).to have_attributes(
      provider_payment_id: "4099260516",
      status: "success",
      payable_payment_status: "succeeded"
    )
    expect(paystack_customer.reload.authorization_code).to eq("AUTH_new")
    expect(client).to have_received(:charge_authorization).with(
      hash_including(
        amount: 50_000,
        authorization_code: "AUTH_test",
        reference:,
        currency: "NGN"
      )
    )
  end

  context "when Paystack returns a failed status" do
    before do
      allow(client).to receive(:charge_authorization).and_return(
        "message" => "Failed",
        "data" => {
          "id" => 4_099_260_516,
          "status" => "failed",
          "reference" => reference,
          "gateway_response" => "Declined"
        }
      )
    end

    it "marks the payment failed and returns a service failure" do
      expect(result).not_to be_success
      expect(result.error.code).to eq("paystack_error")
      expect(payment.reload).to have_attributes(status: "failed", payable_payment_status: "failed")
    end
  end

  context "when the provider customer has no reusable authorization" do
    let(:paystack_customer) do
      create(
        :paystack_customer,
        organization:,
        customer:,
        payment_provider:,
        provider_customer_id: "CUS_test"
      )
    end

    before do
      allow(client).to receive(:initialize_transaction).and_return(
        "data" => {
          "authorization_url" => "https://checkout.paystack.com/test",
          "access_code" => "ACCESS_test",
          "reference" => reference
        }
      )
    end

    it "creates a hosted checkout payment that requires customer action" do
      expect(result).to be_success
      expect(result.payment.reload).to have_attributes(
        status: "requires_action",
        payable_payment_status: "processing"
      )
      expect(result.payment.provider_payment_data).to include(
        "authorization_url" => "https://checkout.paystack.com/test",
        "access_code" => "ACCESS_test",
        "reference" => reference
      )
      expect(client).not_to have_received(:charge_authorization)
      expect(client).to have_received(:initialize_transaction).with(
        hash_including(
          amount: 50_000,
          currency: "NGN",
          reference:,
          callback_url: payment_provider.success_redirect_url
        )
      )
      expect(SendWebhookJob).to have_been_enqueued.with("payment.requires_action", result.payment)
    end
  end

  context "when multiple payment methods are enabled" do
    let(:payment_method) do
      create(
        :payment_method,
        organization:,
        customer:,
        payment_provider:,
        payment_provider_customer: paystack_customer,
        provider_method_id: "AUTH_multiple"
      )
    end

    before do
      organization.update!(feature_flags: ["multiple_payment_methods"])
      payment.update!(payment_method:)
    end

    it "uses the selected payment method authorization" do
      expect(result).to be_success
      expect(client).to have_received(:charge_authorization).with(
        hash_including(authorization_code: "AUTH_multiple")
      )
    end
  end

  context "when the payment currency is unsupported" do
    before { invoice.update!(currency: "EUR") }

    it "does not call Paystack" do
      expect(result).not_to be_success
      expect(client).not_to have_received(:charge_authorization)
      expect(payment.reload).to have_attributes(status: "failed", payable_payment_status: "failed")
    end
  end
end
