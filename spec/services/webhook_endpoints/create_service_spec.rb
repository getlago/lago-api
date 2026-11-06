# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::CreateService do
  subject(:create_service) { described_class.new(organization:, params: create_params) }

  let_it_be(:organization, refind: true) { create(:organization) }
  let(:create_params) do
    {
      webhook_url: "http://foo.bar",
      signature_algo: "hmac",
      name: "Test Webhook",
      event_types: ["customer.created"]
    }
  end

  describe ".call" do
    it "creates the webhook endpoint" do
      result = create_service.call

      expect(result).to be_success
      expect(result.webhook_endpoint.webhook_url).to eq("http://foo.bar")
      expect(result.webhook_endpoint.signature_algo).to eq("hmac")
      expect(result.webhook_endpoint.name).to eq("Test Webhook")
      expect(result.webhook_endpoint.event_types).to eq(["customer.created"])
    end

    context "when creating with partial params" do
      let(:create_params) do
        {
          webhook_url: "http://foo.bar",
          signature_algo: "hmac"
        }
      end

      it "adds only the provided fields" do
        result = create_service.call

        expect(result).to be_success
        # added fields
        expect(result.webhook_endpoint.webhook_url).to eq("http://foo.bar")
        expect(result.webhook_endpoint.signature_algo).to eq("hmac")
        # default fields
        expect(result.webhook_endpoint.name).to be_nil
        expect(result.webhook_endpoint.event_types).to be_nil
      end
    end

    context "when event_types contains a renamed event type" do
      let(:create_params) do
        {
          webhook_url: "http://foo.bar",
          event_types: ["credit_note.provider_refund_failure"]
        }
      end

      it "stores its current name" do
        result = create_service.call

        expect(result).to be_success
        expect(result.webhook_endpoint.event_types).to eq(["credit_note.refund_failure"])
      end
    end

    context "without a signature_algo" do
      let(:create_params) { {webhook_url: "http://foo.bar"} }

      it "signs with JWT" do
        result = create_service.call

        expect(result).to be_success
        expect(result.webhook_endpoint.signature_algo).to eq("jwt")
      end
    end

    context "when signature_algo is unknown" do
      let(:create_params) { {webhook_url: "http://foo.bar", signature_algo: "md5"} }

      it "returns a validation failure with the allowed values, without creating the endpoint" do
        result = nil
        expect { result = create_service.call }.not_to change(WebhookEndpoint, :count)

        expect(result).not_to be_success
        expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
        expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac]})
      end
    end

    context "when signature_algo is null" do
      let(:create_params) { {webhook_url: "http://foo.bar", signature_algo: nil} }

      it "signs with JWT" do
        result = create_service.call

        expect(result).to be_success
        expect(result.webhook_endpoint.signature_algo).to eq("jwt")
      end
    end

    context "when signature_algo is false" do
      let(:create_params) { {webhook_url: "http://foo.bar", signature_algo: false} }

      it "returns a validation failure with the allowed values, without creating the endpoint" do
        result = nil
        expect { result = create_service.call }.not_to change(WebhookEndpoint, :count)

        expect(result).not_to be_success
        expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
        expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac]})
      end
    end

    context "when webhook url is invalid" do
      let(:create_params) do
        {
          webhook_url: "foobar"
        }
      end

      it "returns a validation failure" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error.class).to eq(BaseService::ValidationFailure)
      end
    end

    context "when event types are invalid" do
      let(:create_params) do
        {
          webhook_url: "http://foo.bar",
          event_types: ["invalid.event"]
        }
      end

      it "returns the sentence to v1 and GraphQL and a token to native v2" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error.class).to eq(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(event_types: ["contains invalid types: [\"invalid.event\"]"])
        expect(result.error.codes).to eq(event_types: ["value_is_invalid"])
      end
    end

    context "when the organization has reached the endpoint limit" do
      before do
        create_list(:webhook_endpoint, WebhookEndpoint::LIMIT - organization.webhook_endpoints.count, organization:)
      end

      it "returns the sentence to v1 and GraphQL and a token to native v2" do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error.messages).to eq(base: ["Maximum number of webhook endpoints was reached"])
        expect(result.error.codes).to eq(base: ["exceeded_limit"])
      end
    end
  end
end
