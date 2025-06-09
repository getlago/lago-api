# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Webhooks::PaymentIntentPaymentFailedService do
  subject(:event_service) { described_class.new(organization_id: organization.id, event:) }

  let(:event) { ::Stripe::Event.construct_from(JSON.parse(event_json)) }
  let(:organization) { create(:organization) }

  context "when payment intent event" do
    let(:event_json) { get_stripe_fixtures("webhooks/payment_intent_payment_failed.json") }

    it "updates the payment status and save the payment method" do
      expect_any_instance_of(Invoices::Payments::StripeService).to receive(:update_payment_status) # rubocop:disable RSpec/AnyInstance
        .with(
          organization_id: organization.id,
          status: "failed",
          stripe_payment: PaymentProviders::StripeProvider::StripePayment
        ).and_call_original

      create(:payment, provider_payment_id: event.data.object.id)

      result = event_service.call

      expect(result).to be_success
    end
  end

  context "when payment intent event for a payment request" do
    let(:event_json) do
      json = get_stripe_fixtures("webhooks/payment_intent_payment_failed.json")
      h = JSON.parse(json)
      h["data"]["object"]["metadata"] = {
        lago_payable_type: "PaymentRequest",
        lago_payment_request_id: "a587e552-36bc-4334-81f2-abcbf034ad3f"
      }
      h.to_json
    end

    it "routes the event to an other service" do
      expect_any_instance_of(PaymentRequests::Payments::StripeService).to receive(:update_payment_status) # rubocop:disable RSpec/AnyInstance
        .with(
          organization_id: organization.id,
          status: "failed",
          stripe_payment: PaymentProviders::StripeProvider::StripePayment
        ).and_call_original

      payment = create(:payment, provider_payment_id: event.data.object.id)
      create(:payment_request, customer: create(:customer, organization:), payments: [payment])

      result = event_service.call

      expect(result).to be_success
    end
  end

  context "when payment intent event with an invalid payable type" do
    let(:event_json) do
      json = get_stripe_fixtures("webhooks/payment_intent_payment_failed.json")
      h = JSON.parse(json)
      h["data"]["object"]["metadata"]["lago_payable_type"] = "InvalidPayableTypeName"
      h.to_json
    end

    it do
      expect { event_service.call }.to raise_error(NameError, "Invalid lago_payable_type: InvalidPayableTypeName")
    end
  end
end
