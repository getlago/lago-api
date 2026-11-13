# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::CreateService do
  subject(:create_service) { described_class.new(organization:, params: create_params, signature_algo_rule:) }

  include_context "with mocked security logger"

  let_it_be(:organization, refind: true) { create(:organization) }
  let(:signature_algo_rule) { nil }
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
      expect(result.webhook_endpoint.signing_keys).to be_empty
    end

    it "produces the webhook_endpoint.created security log" do
      create_service.call

      expect(security_logger).to have_received(:produce).with(
        organization:,
        log_type: "webhook_endpoint",
        log_event: "webhook_endpoint.created",
        resources: {webhook_url: "http://foo.bar", signature_algo: "hmac"}
      )
    end

    it "enqueues the Segment job after commit" do
      result = nil

      expect { result = create_service.call }.to have_enqueued_job_after_commit(SegmentTrackJob).with(
        membership_id: nil,
        event: "webhook_endpoint_created",
        properties: {
          webhook_endpoint_id: kind_of(String),
          organization_id: organization.id,
          webhook_url: "http://foo.bar"
        }
      )
      expect(SegmentTrackJob).to have_been_enqueued.with(
        membership_id: nil,
        event: "webhook_endpoint_created",
        properties: {
          webhook_endpoint_id: result.webhook_endpoint.id,
          organization_id: organization.id,
          webhook_url: "http://foo.bar"
        }
      )
    end

    context "when an outer transaction rolls back" do
      it "creates no endpoint, produces no security log and enqueues no Segment job" do
        expect do
          ApplicationRecord.transaction do
            create_service.call
            raise StandardError, "rollback"
          end
        rescue
          nil
        end.not_to change(WebhookEndpoint, :count)

        expect(security_logger).not_to have_received(:produce)
        expect(SegmentTrackJob).not_to have_been_enqueued
      end
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
        expect(result.webhook_endpoint.signing_keys).to be_empty
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

      it "returns a validation failure with the allowed values, without creating the endpoint" do
        result = nil
        expect { result = create_service.call }.not_to change(WebhookEndpoint, :count)

        expect(result).not_to be_success
        expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
        expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac]})
      end

      context "with the standard_webhooks_signature flag" do
        before { organization.enable_feature_flag!(:standard_webhooks_signature) }

        it "creates a standard_webhooks endpoint with one signing key" do
          result = create_service.call

          expect(result).to be_success
          expect(result.webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
          expect(result.webhook_endpoint.signing_keys.pluck(:organization_id)).to eq([organization.id])
        end

        context "when the signing key cannot be created" do
          let(:key_failure) { BaseService::FailedResult.new(BaseService::Result.new, "key failure") }

          before { allow(WebhookEndpoints::SigningKeys::CreateService).to receive(:call!).and_raise(key_failure) }

          it "raises and leaves no endpoint, security log or Segment job" do
            expect { create_service.call }.to raise_error(BaseService::FailedResult, "key failure")
              .and not_change(WebhookEndpoint, :count)
              .and not_change(WebhookEndpointSigningKey, :count)

            expect(security_logger).not_to have_received(:produce)
            expect(SegmentTrackJob).not_to have_been_enqueued
          end
        end
      end
    end

    context "with the native v2 rule" do
      let(:signature_algo_rule) { WebhookEndpoint::V2_SIGNATURE_ALGO_RULE }

      context "without a signature_algo" do
        let(:create_params) { {webhook_url: "http://foo.bar"} }

        it "creates a standard_webhooks endpoint with one signing key" do
          result = create_service.call

          expect(result).to be_success
          expect(result.webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
          expect(result.webhook_endpoint.signing_keys.count).to eq(1)
        end
      end

      context "when signature_algo is standard_webhooks" do
        let(:create_params) { {webhook_url: "http://foo.bar", signature_algo: "standard_webhooks"} }

        it "creates a standard_webhooks endpoint with one signing key, even without the flag" do
          result = create_service.call

          expect(result).to be_success
          expect(result.webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
          expect(result.webhook_endpoint.signing_keys.count).to eq(1)
        end
      end

      %w[jwt hmac md5].each do |signature_algo|
        context "when signature_algo is #{signature_algo}" do
          let(:create_params) { {webhook_url: "http://foo.bar", signature_algo:} }

          it "returns a validation failure with the v2 allowed values, without creating the endpoint" do
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

      it "produces no security log and enqueues no Segment job" do
        expect { create_service.call }.not_to have_enqueued_job(SegmentTrackJob)
        expect(security_logger).not_to have_received(:produce)
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
