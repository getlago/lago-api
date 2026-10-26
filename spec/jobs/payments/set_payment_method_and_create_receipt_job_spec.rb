# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::SetPaymentMethodAndCreateReceiptJob do
  before_all do
    create_default(:organization)
    create_default(:invoice)
  end

  let(:payment) { create(:payment) }
  let(:provider_payment_method_id) { "pm_001" }

  before do
    allow(Payments::SetPaymentMethodDataService)
      .to receive(:call!).with(payment:, provider_payment_method_id:).and_return(Payments::SetPaymentMethodDataService::Result.new)
  end

  it "calls the service" do
    described_class.perform_now(payment:, provider_payment_method_id:)

    expect(Payments::SetPaymentMethodDataService).to have_received(:call!)
  end

  context "with customer payment_method" do
    let(:customer) { payment.customer }
    let(:payment_method) { create(:payment_method, customer:, provider_method_id: provider_payment_method_id) }

    before { payment_method }

    it "attachs the payment method to the payment" do
      described_class.perform_now(payment:, provider_payment_method_id:)
      expect(payment.payment_method_id).to eq(payment_method.id)
    end
  end

  context "when the Stripe payment method is attached to the customer's Stripe customer and unknown to Lago" do
    # The fixture payment method belongs to this Stripe customer, as a card saved through a payment link does.
    let(:provider_payment_method_id) { "pm_1RTjuYQ8iJWBZFaMCfXmSmQD" }
    let(:customer) { create(:customer) }
    let(:stripe_customer) { create(:stripe_customer, customer:, provider_customer_id: "cus_SOWyVXSNy6uKcg") }
    let(:payment) { create(:payment, payable: create(:invoice, customer:), payment_provider_customer: stripe_customer) }

    before do
      allow(Payments::SetPaymentMethodDataService).to receive(:call!).and_call_original

      stub_request(:get, %r{/v1/payment_methods/#{provider_payment_method_id}}).and_return(
        status: 200, body: get_stripe_fixtures("retrieve_payment_method_response.json", version: "2025-04-30.basil")
      )
    end

    it "creates a default payment method with the card details and links it to the payment" do
      described_class.perform_now(payment:, provider_payment_method_id:)

      payment_method = customer.payment_methods.sole
      expect(payment_method).to have_attributes(
        provider_method_id: provider_payment_method_id,
        payment_provider_customer: stripe_customer,
        is_default: true,
        details: hash_including("type" => "card", "brand" => "visa", "last4" => "4242")
      )
      expect(payment.reload.payment_method_id).to eq(payment_method.id)
    end

    context "with an existing default payment method" do
      let!(:default_payment_method) { create(:payment_method, customer:, provider_method_id: "pm_default", is_default: true) }

      it "creates a payment method that is not default and keeps the existing default" do
        described_class.perform_now(payment:, provider_payment_method_id:)

        payment_method = customer.payment_methods.find_by!(provider_method_id: provider_payment_method_id)
        expect(payment_method.is_default).to be(false)
        expect(default_payment_method.reload.is_default).to be(true)
        expect(payment.reload.payment_method_id).to eq(payment_method.id)
      end
    end

    context "when the Stripe payment method belongs to another Stripe customer" do
      let(:stripe_payment_method_json) do
        JSON.parse(get_stripe_fixtures("retrieve_payment_method_response.json", version: "2025-04-30.basil"))
          .merge("customer" => "cus_another").to_json
      end

      before do
        stub_request(:get, %r{/v1/payment_methods/#{provider_payment_method_id}}).and_return(status: 200, body: stripe_payment_method_json)
      end

      it "does not create a payment method and stores the payment data" do
        expect { described_class.perform_now(payment:, provider_payment_method_id:) }.not_to change(PaymentMethod, :count)

        expect(payment.reload.payment_method_id).to be_nil
        expect(payment.provider_payment_method_data).to include("brand" => "visa", "last4" => "4242")
      end
    end

    context "when the Stripe payment method has no customer" do
      let(:stripe_payment_method_json) do
        JSON.parse(get_stripe_fixtures("retrieve_payment_method_response.json", version: "2025-04-30.basil"))
          .merge("customer" => nil).to_json
      end

      before do
        stub_request(:get, %r{/v1/payment_methods/#{provider_payment_method_id}}).and_return(status: 200, body: stripe_payment_method_json)
      end

      it "does not create a payment method and stores the payment data" do
        expect { described_class.perform_now(payment:, provider_payment_method_id:) }.not_to change(PaymentMethod, :count)

        expect(payment.reload.payment_method_id).to be_nil
        expect(payment.provider_payment_method_data).to include("brand" => "visa", "last4" => "4242")
      end
    end

    context "when a payment method with the same provider_method_id already exists" do
      let!(:payment_method) do
        create(:payment_method, customer:, payment_provider_customer: stripe_customer, provider_method_id: provider_payment_method_id)
      end

      it "links the existing payment method and fills its details" do
        expect { described_class.perform_now(payment:, provider_payment_method_id:) }.not_to change(PaymentMethod, :count)

        expect(payment.reload.payment_method_id).to eq(payment_method.id)
        expect(payment_method.reload.details).to include("type" => "card", "brand" => "visa", "last4" => "4242")
      end
    end

    context "when the job runs twice for the same payment" do
      it "creates only one payment method" do
        described_class.perform_now(payment:, provider_payment_method_id:)
        described_class.perform_now(payment: payment.reload, provider_payment_method_id:)

        expect(customer.payment_methods.pluck(:provider_method_id)).to eq([provider_payment_method_id])
        expect(payment.reload.payment_method_id).to eq(customer.payment_methods.sole.id)
      end
    end

    context "without a Stripe customer" do
      let(:payment) { create(:payment, payable: create(:invoice, customer:), payment_provider_customer: nil) }

      it "does not create a payment method" do
        expect { described_class.perform_now(payment:, provider_payment_method_id:) }.not_to change(PaymentMethod, :count)

        expect(payment.reload.payment_method_id).to be_nil
        expect(payment.provider_payment_method_data).to include("brand" => "visa", "last4" => "4242")
      end
    end
  end
end
