# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentProviders::Adyen::HandleIncomingWebhookService do
  let(:webhook_service) { described_class.new(organization_id:, body:, code:) }
  let(:organization_id) { organization.id }
  let(:adyen_provider) { create(:adyen_provider, organization:, hmac_key:) }
  let(:hmac_key) { "a1b2c3d4e5f6" }
  let(:code) { nil }
  let(:body) do
    JSON.parse(event_response_json)["notificationItems"].first&.dig("NotificationRequestItem")
  end
  let(:event_response_json) do
    path = Rails.root.join("spec/fixtures/adyen/webhook_authorisation_response.json")
    File.read(path)
  end

  let_it_be(:organization) { create(:organization) }

  before { adyen_provider }

  describe "#call" do
    context "when the signature is valid" do
      let(:validator) { instance_double(::Adyen::Utils::HmacValidator) }

      before do
        allow(::Adyen::Utils::HmacValidator).to receive(:new).and_return(validator)
        allow(validator).to receive(:valid_notification_hmac?).with(body, hmac_key).and_return(true)
      end

      it "checks the webhook" do
        result = webhook_service.call

        expect(result).to be_success

        expect(result.event).to eq(body)
        expect(PaymentProviders::Adyen::HandleEventJob).to have_been_enqueued
      end
    end

    context "when the hmac key is missing" do
      let(:hmac_key) { nil }

      it "returns an error without enqueuing the event" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to eq("Invalid signature")
        expect(PaymentProviders::Adyen::HandleEventJob).not_to have_been_enqueued
      end
    end

    context "when organization does not exist" do
      let(:organization_id) { "123456789" }

      it "returns an error" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to eq("Organization not found")
      end
    end

    context "when payment provider does not exist" do
      let(:adyen_provider) { nil }

      it "returns an error" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to eq("Payment provider not found")
      end
    end

    context "when failing to validate the signature" do
      let(:adyen_provider) { create(:adyen_provider, organization:, hmac_key: "123") }

      it "returns an error" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to eq("Invalid signature")
      end
    end

    context "when multiple payment providers exists and no code is provided" do
      before { create(:adyen_provider, organization:) }

      it "returns an error" do
        result = webhook_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("webhook_error")
        expect(result.error.error_message).to eq("Payment provider code is missing")
      end
    end
  end
end
