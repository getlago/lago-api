# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::Payments::CheckAbandonedAuthenticationService do
  subject(:check_service) { described_class.new(payment:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:payment) { create(:payment, :requires_action, payable: create(:invoice, customer:, organization:), customer:, organization:) }

  let(:intent_status) { "requires_action" }
  let(:method_type) { "card" }
  let(:next_action_type) { "redirect_to_url" }

  let(:intent) do
    ::Stripe::PaymentIntent.construct_from(
      id: payment.provider_payment_id,
      status: intent_status,
      payment_method: method_type.nil? ? nil : {id: "pm_1", type: method_type},
      next_action: next_action_type.nil? ? nil : {type: next_action_type}
    )
  end

  before { allow(::Stripe::PaymentIntent).to receive(:retrieve).and_return(intent) }

  describe "#call" do
    it "reads the live intent rather than the stored snapshot" do
      check_service.call

      expect(::Stripe::PaymentIntent).to have_received(:retrieve).with(
        {id: payment.provider_payment_id, expand: ["payment_method"]},
        {api_key: payment.payment_provider.secret_key}
      )
    end

    it "reports a card challenge still awaiting the customer as abandoned" do
      expect(check_service.call.abandoned).to be(true)
    end

    context "when the challenge is driven by the Stripe SDK" do
      let(:next_action_type) { "use_stripe_sdk" }

      it "reports it as abandoned" do
        expect(check_service.call.abandoned).to be(true)
      end
    end

    context "when the intent is waiting on an incoming wire" do
      let(:method_type) { "customer_balance" }
      let(:next_action_type) { "display_bank_transfer_instructions" }

      it "is not abandoned" do
        expect(check_service.call.abandoned).to be(false)
      end
    end

    context "when the intent is a redirect on a non-card method" do
      let(:method_type) { "ideal" }

      it "is not abandoned" do
        expect(check_service.call.abandoned).to be(false)
      end
    end

    context "when the customer completed the challenge since" do
      let(:intent_status) { "succeeded" }

      it "is not abandoned" do
        expect(check_service.call.abandoned).to be(false)
      end
    end

    context "when the intent carries no payment method" do
      let(:method_type) { nil }

      it "is not abandoned" do
        expect(check_service.call.abandoned).to be(false)
      end
    end

    context "when the intent cannot be read" do
      before do
        allow(::Stripe::PaymentIntent).to receive(:retrieve).and_raise(::Stripe::InvalidRequestError.new("no such intent", nil))
      end

      it "is not abandoned" do
        expect(check_service.call.abandoned).to be(false)
      end
    end

    context "when the payment has no provider payment id" do
      before { payment.update!(provider_payment_id: nil) }

      it "is not abandoned without calling the provider" do
        expect(check_service.call.abandoned).to be(false)
        expect(::Stripe::PaymentIntent).not_to have_received(:retrieve)
      end
    end
  end
end
