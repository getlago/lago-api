# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Stripe::HandleIncomingWebhookService, type: :service do
  subject(:result) do
    described_class.call(
      organization_id: organization.id,
      body: event.to_json,
      signature: "signature",
      code:
    )
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:code) { nil }
  let(:stripe_provider) { create(:stripe_provider, organization:) }
  let(:event_result) { Stripe::Event.construct_from(event) }

  let(:event) do
    path = Rails.root.join("spec/fixtures/stripe/payment_intent_event.json")
    JSON.parse(File.read(path))
  end

  before { stripe_provider }

  it "checks the webhook" do
    allow(::Stripe::Webhook).to receive(:construct_event)
      .and_return(event_result)

    expect(result).to be_success
    expect(result.event).to eq(event_result)
    expect(PaymentProviders::Stripe::HandleEventJob).to have_been_enqueued
  end

  context "when failing to parse payload" do
    it "returns an error" do
      allow(::Stripe::Webhook).to receive(:construct_event)
        .and_raise(JSON::ParserError)

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to eq("Invalid payload")
    end
  end

  context "when failing to validate the signature" do
    it "returns an error" do
      allow(::Stripe::Webhook).to receive(:construct_event)
        .and_raise(
          ::Stripe::SignatureVerificationError.new(
            "error", "signature", http_body: event.to_json
          )
        )

      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::ServiceFailure)
      expect(result.error.code).to eq("webhook_error")
      expect(result.error.error_message).to eq("Invalid signature")
    end
  end
end
