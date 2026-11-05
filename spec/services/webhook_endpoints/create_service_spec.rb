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
    %w[jwt hmac].each do |signature_algo|
      context "when signature_algo is #{signature_algo}" do
        let(:create_params) { {webhook_url: "http://foo.bar", signature_algo:} }

        it "creates no signing key" do
          expect { create_service.call }.not_to change(WebhookEndpointSigningKey, :count)
        end
      end
    end

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

    context "when signature_algo is standard_webhooks" do
      let(:create_params) { {webhook_url: "http://foo.bar", signature_algo: "standard_webhooks"} }

      it "returns a validation failure without the rollout flag, without creating the endpoint" do
        result = nil
        expect { result = create_service.call }.not_to change(WebhookEndpoint, :count)

        expect(result).not_to be_success
        expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
        expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac]})
      end

      context "when the organization has the standard_webhooks_signature flag" do
        before { organization.enable_feature_flag!(:standard_webhooks_signature) }

        it "signs with Standard Webhooks" do
          result = create_service.call

          expect(result).to be_success
          expect(result.webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
        end

        it "creates one signing key with a whsec_ secret" do
          result = create_service.call

          expect(result.webhook_endpoint.signing_keys.count).to eq(1)
          expect(result.webhook_endpoint.signing_keys.sole.secret_key).to start_with("whsec_")
        end

        context "when the endpoint is invalid" do
          let(:create_params) { {webhook_url: "foobar", signature_algo: "standard_webhooks"} }

          it "creates neither the endpoint nor a signing key" do
            result = nil
            expect { result = create_service.call }
              .to not_change(WebhookEndpoint, :count)
              .and not_change(WebhookEndpointSigningKey, :count)

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::ValidationFailure)
          end
        end

        context "when the signing key cannot be created" do
          before do
            allow(WebhookEndpoints::SigningKeys::EnsureService).to receive(:call!)
              .and_raise(ActiveRecord::RecordInvalid.new(WebhookEndpointSigningKey.new))
          end

          it "rolls back the endpoint" do
            result = nil
            expect { result = create_service.call }.not_to change(WebhookEndpoint, :count)

            expect(result).not_to be_success
          end
        end
      end
    end

    context "when the organization has the standard_webhooks_signature flag" do
      before { organization.enable_feature_flag!(:standard_webhooks_signature) }

      context "without a signature_algo" do
        let(:create_params) { {webhook_url: "http://foo.bar"} }

        it "still signs with JWT" do
          result = create_service.call

          expect(result).to be_success
          expect(result.webhook_endpoint.signature_algo).to eq("jwt")
        end
      end

      context "when signature_algo is unknown" do
        let(:create_params) { {webhook_url: "http://foo.bar", signature_algo: "md5"} }

        it "lists the three algorithms in the validation failure" do
          result = create_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
          expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac standard_webhooks]})
        end
      end
    end

    context "when the organization has the product catalog" do
      before { organization.enable_feature_flag!(:product_catalog) }

      [[{}, "without a signature_algo"], [{signature_algo: nil}, "when signature_algo is null"], [{signature_algo: "standard_webhooks"}, "when signature_algo is standard_webhooks"]].each do |algo_params, label|
        context label do
          let(:create_params) { {webhook_url: "http://foo.bar", **algo_params} }

          it "signs with Standard Webhooks without the rollout flag and creates one signing key" do
            result = create_service.call

            expect(result).to be_success
            expect(result.webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
            expect(result.webhook_endpoint.signing_keys.sole.secret_key).to start_with("whsec_")
          end
        end
      end

      [["jwt", "jwt"], ["hmac", "hmac"], ["md5", "unknown"]].each do |signature_algo, label|
        context "when signature_algo is #{label}" do
          let(:create_params) { {webhook_url: "http://foo.bar", signature_algo:} }

          it "returns a validation failure allowing only standard_webhooks, without creating the endpoint" do
            result = nil
            expect { result = create_service.call }.not_to change(WebhookEndpoint, :count)

            expect(result).not_to be_success
            expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
            expect(result.error.meta).to eq(signature_algo: {allowed_values: ["standard_webhooks"]})
          end
        end
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
