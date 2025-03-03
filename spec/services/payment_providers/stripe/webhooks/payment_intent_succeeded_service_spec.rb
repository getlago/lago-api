# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::PaymentIntentSucceededService, type: :service do
  subject(:event_service) { described_class.new(organization_id: organization.id, event:) }

  let(:event) { ::Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:organization) { create(:organization) }

  let(:event_json) do
    path = Rails.root.join("spec/fixtures/stripe/#{fixtures_filename}")
    File.read(path)
  end

  context "when payment intent event" do
    let(:fixtures_filename) { "payment_intent_event.json" }

    it "updates the payment status and save the payment method" do
      expect_any_instance_of(Invoices::Payments::StripeService).to receive(:update_payment_status) # rubocop:disable RSpec/AnyInstance
        .with(
          organization_id: organization.id,
          status: "succeeded",
          stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
            id: "pi_3Qu0oXQ8iJWBZFaM2cc2RG6D",
            status: "succeeded",
            metadata: {
              invoice_type: "one_off",
              lago_customer_id: "475c46b6-b907-4e5e-8dc7-934377b1cb3c",
              invoice_issuing_date: "2025-02-19",
              lago_invoice_id: "a587e552-36bc-4334-81f2-abcbf034ad3f"
            }
          )
        ).and_call_original

      create(:payment, provider_payment_id: event.data.object.id)

      result = event_service.call

      expect(result).to be_success

      # expect(payment.reload.provider_payment_method_data).to eq({
      #   "id" => "pm_1Qu0lNQ8iJWBZFaMkKPH3KFv",
      #   "type" => "card",
      #   "brand" => "visa",
      #   "last4" => "4242"
      # })
    end
  end

  context "when payment intent event for a payment request" do
    let(:fixtures_filename) { "payment_intent_event_payment_request.json" }

    it "routes the event to an other service" do
      expect_any_instance_of(PaymentRequests::Payments::StripeService).to receive(:update_payment_status) # rubocop:disable RSpec/AnyInstance
        .with(
          organization_id: organization.id,
          status: "succeeded",
          stripe_payment: PaymentProviders::StripeProvider::StripePayment.new(
            id: "pi_3Qu0oXQ8iJWBZFaM2cc2RG6D",
            status: "succeeded",
            metadata: {
              lago_payment_request_id: "a587e552-36bc-4334-81f2-abcbf034ad3f",
              lago_payable_type: "PaymentRequest"
            }
          )
        ).and_call_original

      payment = create(:payment, provider_payment_id: event.data.object.id)
      create(:payment_request, customer: create(:customer, organization:), payments: [payment])

      result = event_service.call

      expect(result).to be_success
      # expect(payment.reload.provider_payment_method_data).to eq({
      #   "id" => "pm_1Qu0lNQ8iJWBZFaMkKPH3KFv",
      #   "type" => "card",
      #   "brand" => "visa",
      #   "last4" => "4242"
      # })
    end
  end

  context "when payment intent event with an invalid payable type" do
    let(:fixtures_filename) { "payment_intent_event_invalid_payable_type.json" }

    it do
      expect { event_service.call }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
    end
  end
end
