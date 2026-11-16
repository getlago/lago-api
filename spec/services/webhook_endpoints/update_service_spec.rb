# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::UpdateService do
  subject(:update_service) do
    described_class.new(id: webhook_endpoint.id, organization:, params: update_params, signature_algo_rule:)
  end

  include_context "with mocked security logger"

  # let, not let_it_be: the concurrency example commits its rows and empties the tables.
  let(:organization) { create(:organization) }
  let(:signature_algo_rule) { nil }
  let!(:webhook_endpoint) { create(:webhook_endpoint, organization:, name: "Original Webhook", event_types: ["customer.created"]) }
  let(:update_params) do
    {
      webhook_url: "http://foo.bar",
      signature_algo: "hmac",
      name: "Updated Webhook",
      event_types: ["customer.updated"]
    }
  end

  describe ".call" do
    it "updates the webhook endpoint" do
      result = update_service.call

      expect(result).to be_success
      expect(result.webhook_endpoint.webhook_url).to eq("http://foo.bar")
      expect(result.webhook_endpoint.signature_algo).to eq("hmac")
      expect(result.webhook_endpoint.name).to eq("Updated Webhook")
      expect(result.webhook_endpoint.event_types).to eq(["customer.updated"])
      expect(result.webhook_endpoint.signing_keys).to be_empty
    end

    context "when updating with partial params" do
      let(:update_params) do
        {
          webhook_url: "http://foo.bar",
          signature_algo: "hmac"
        }
      end

      it "updates only the provided fields" do
        result = update_service.call

        expect(result).to be_success
        # updated fields
        expect(result.webhook_endpoint.webhook_url).to eq("http://foo.bar")
        expect(result.webhook_endpoint.signature_algo).to eq("hmac")
        # unchanged fields
        expect(result.webhook_endpoint.name).to eq("Original Webhook")
        expect(result.webhook_endpoint.event_types).to eq(["customer.created"])
      end
    end

    it_behaves_like "produces a security log", "webhook_endpoint.updated" do
      before { update_service.call }
    end

    it "logs the url and signature_algo changes" do
      old_url = webhook_endpoint.webhook_url
      old_algo = webhook_endpoint.signature_algo
      update_service.call

      expect(security_logger).to have_received(:produce).with(
        organization:,
        log_type: "webhook_endpoint",
        log_event: "webhook_endpoint.updated",
        resources: {
          webhook_url: {deleted: old_url, added: "http://foo.bar"},
          signature_algo: {deleted: old_algo, added: "hmac"}
        }
      )
    end

    context "when an outer transaction rolls back" do
      it "keeps the endpoint and produces no security log" do
        expect do
          ApplicationRecord.transaction do
            update_service.call
            raise StandardError, "rollback"
          end
        rescue
          nil
        end.not_to change { webhook_endpoint.reload.attributes }

        expect(security_logger).not_to have_received(:produce)
      end
    end

    context "when an outer transaction changes the endpoint again before committing" do
      let(:update_params) { {webhook_url: "http://foo.bar"} }

      it "logs the change made by this update" do
        old_url = webhook_endpoint.webhook_url

        ApplicationRecord.transaction do
          # Same instance, so its previous_changes no longer hold the url change at commit.
          update_service.call.webhook_endpoint.update!(name: "Renamed")

          expect(security_logger).not_to have_received(:produce)
        end

        expect(security_logger).to have_received(:produce).once.with(
          organization:,
          log_type: "webhook_endpoint",
          log_event: "webhook_endpoint.updated",
          resources: {webhook_url: {deleted: old_url, added: "http://foo.bar"}}
        )
      end
    end

    [["md5", "unknown"], [nil, "null"]].each do |signature_algo, label|
      context "when signature_algo is #{label}" do
        let(:update_params) { {name: "Updated Webhook", signature_algo:} }

        it "returns a validation failure with the allowed values, without changing the endpoint" do
          result = nil
          expect { result = update_service.call }.not_to change { webhook_endpoint.reload.attributes }

          expect(result).not_to be_success
          expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
          expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac]})
        end
      end
    end

    context "when signature_algo changes to standard_webhooks" do
      let(:update_params) { {signature_algo: "standard_webhooks"} }

      it "returns a validation failure with the allowed values, without changing the endpoint" do
        result = nil
        expect { result = update_service.call }.not_to change { webhook_endpoint.reload.attributes }

        expect(result).not_to be_success
        expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
        expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac]})
      end

      context "with the standard_webhooks_signature flag" do
        before { organization.enable_feature_flag!(:standard_webhooks_signature) }

        it "switches the endpoint to standard_webhooks with one signing key" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
          expect(webhook_endpoint.signing_keys.pluck(:organization_id)).to eq([organization.id])
        end

        it "logs the signature_algo change" do
          update_service.call

          expect(security_logger).to have_received(:produce).with(
            organization:,
            log_type: "webhook_endpoint",
            log_event: "webhook_endpoint.updated",
            resources: {
              webhook_url: webhook_endpoint.webhook_url,
              signature_algo: {deleted: "jwt", added: "standard_webhooks"}
            }
          )
        end

        context "when the signing key cannot be created" do
          before do
            allow(WebhookEndpoints::SigningKeys::CreateService).to receive(:call!)
              .and_raise(BaseService::FailedResult.new(BaseService::Result.new, "key failure"))
          end

          it "raises, keeps the endpoint unchanged and produces no security log" do
            expect { update_service.call }.to raise_error(BaseService::FailedResult, "key failure")
              .and not_change { webhook_endpoint.reload.attributes }

            expect(security_logger).not_to have_received(:produce)
          end
        end

        context "when the endpoint switched away from standard_webhooks earlier" do
          let!(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :hmac) }
          let!(:kept_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

          it "reuses the kept signing key" do
            result = update_service.call

            expect(result).to be_success
            expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
            expect(webhook_endpoint.signing_keys.pluck(:id)).to eq([kept_key.id])
          end
        end

        context "when two updates switch the endpoint at once", transaction: false do
          it "creates a single signing key" do
            endpoint_id = webhook_endpoint.id # materialize on this connection before the threads read it
            organization_id = organization.id

            results = Array.new(2) do
              Thread.new do
                ActiveRecord::Base.connection_pool.with_connection do
                  described_class.call(id: endpoint_id, organization: Organization.find(organization_id), params: update_params)
                end
              end
            end.map(&:value)

            expect(results).to all(be_success)
            expect(WebhookEndpoint.find(endpoint_id).signature_algo).to eq("standard_webhooks")
            expect(WebhookEndpointSigningKey.where(webhook_endpoint_id: endpoint_id).count).to eq(1)
          end
        end
      end
    end

    context "when a standard_webhooks endpoint with a signing key is updated" do
      let!(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }
      let!(:signing_key) { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

      context "when it switches to hmac" do
        let(:update_params) { {signature_algo: "hmac"} }

        it "keeps its signing key" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload.signature_algo).to eq("hmac")
          expect(webhook_endpoint.signing_keys.pluck(:id)).to eq([signing_key.id])
        end
      end

      context "when only its name changes" do
        let(:update_params) { {name: "Renamed"} }

        it "creates no other signing key" do
          expect { update_service.call }.not_to change(WebhookEndpointSigningKey, :count)

          expect(webhook_endpoint.signing_keys.pluck(:id)).to eq([signing_key.id])
        end
      end
    end

    context "when the endpoint signs with standard_webhooks and the organization has no flag" do
      let!(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }

      context "when the update sends the current signature_algo" do
        let(:update_params) { {name: "Renamed", signature_algo: "standard_webhooks"} }

        it "accepts it" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload).to have_attributes(name: "Renamed", signature_algo: "standard_webhooks")
        end
      end

      context "when the update does not send signature_algo" do
        let(:update_params) { {name: "Renamed", webhook_url: "http://foo.bar", event_types: ["customer.updated"]} }

        it "updates the name, url and event types without creating a signing key" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload).to have_attributes(
            name: "Renamed",
            webhook_url: "http://foo.bar",
            event_types: ["customer.updated"],
            signature_algo: "standard_webhooks"
          )
          # Only a switch to standard_webhooks creates the key.
          expect(webhook_endpoint.signing_keys).to be_empty
        end
      end
    end

    context "with the native v2 rule" do
      let(:signature_algo_rule) { WebhookEndpoint::V2_SIGNATURE_ALGO_RULE }

      context "when a hmac endpoint is updated with its current signature_algo" do
        let!(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :hmac) }
        let(:update_params) { {name: "Renamed", signature_algo: "hmac"} }

        it "accepts it" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload).to have_attributes(name: "Renamed", signature_algo: "hmac")
        end
      end

      context "when a hmac endpoint is updated without signature_algo" do
        let!(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :hmac) }
        let(:update_params) { {name: "Renamed", webhook_url: "http://foo.bar", event_types: ["customer.updated"]} }

        it "updates the name, url and event types" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload).to have_attributes(
            name: "Renamed",
            webhook_url: "http://foo.bar",
            event_types: ["customer.updated"],
            signature_algo: "hmac"
          )
        end
      end

      context "when a standard_webhooks endpoint changes to jwt" do
        let!(:webhook_endpoint) { create(:webhook_endpoint, organization:, signature_algo: :standard_webhooks) }
        let(:update_params) { {signature_algo: "jwt"} }

        it "returns a validation failure with the v2 allowed values, without changing the endpoint" do
          result = nil
          expect { result = update_service.call }.not_to change { webhook_endpoint.reload.attributes }

          expect(result).not_to be_success
          expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
          expect(result.error.meta).to eq(signature_algo: {allowed_values: ["standard_webhooks"]})
        end
      end

      context "when a jwt endpoint changes to standard_webhooks" do
        let(:update_params) { {signature_algo: "standard_webhooks"} }

        it "switches the endpoint to standard_webhooks with one signing key, even without the flag" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
          expect(webhook_endpoint.signing_keys.count).to eq(1)
        end
      end

      context "when signature_algo is null" do
        let(:update_params) { {signature_algo: nil} }

        it "returns a validation failure with the v2 allowed values" do
          result = update_service.call

          expect(result).not_to be_success
          expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
          expect(result.error.meta).to eq(signature_algo: {allowed_values: ["standard_webhooks"]})
        end
      end
    end

    context "when the endpoint belongs to another organization" do
      let!(:webhook_endpoint) { create(:webhook_endpoint, organization: create(:organization)) }
      let(:update_params) { {name: "Renamed"} }

      it "returns a not found error, without changing the endpoint" do
        result = nil
        expect { result = update_service.call }.not_to change { webhook_endpoint.reload.attributes }

        expect(result).not_to be_success
        expect(result.error.message).to eq("webhook_endpoint_not_found")
      end
    end

    context "when webhook endpoint does not exist" do
      let(:webhook_endpoint) { instance_double(WebhookEndpoint, id: "123456") }

      it "returns a not found error" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.message).to eq("webhook_endpoint_not_found")
      end

      it_behaves_like "does not produce a security log" do
        before { update_service.call }
      end
    end

    context "when webhook url is invalid" do
      let(:update_params) do
        {
          webhook_url: "foobar"
        }
      end

      it "returns a validation failure" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.class).to eq(BaseService::ValidationFailure)
      end

      it_behaves_like "does not produce a security log" do
        before { update_service.call }
      end
    end

    context "when event types are invalid" do
      let(:update_params) do
        {
          event_types: ["invalid.event"]
        }
      end

      it "returns the sentence to v1 and GraphQL and a token to native v2" do
        result = update_service.call

        expect(result).not_to be_success
        expect(result.error.class).to eq(BaseService::ValidationFailure)
        expect(result.error.messages).to eq(event_types: ["contains invalid types: [\"invalid.event\"]"])
        expect(result.error.codes).to eq(event_types: ["value_is_invalid"])
      end
    end

    context "when event_types contains a renamed event type" do
      let(:update_params) { {event_types: ["customer.updated", "credit_note.provider_refund_failure"]} }

      it "stores its current name" do
        result = update_service.call

        expect(result).to be_success
        expect(result.webhook_endpoint.event_types).to eq(["customer.updated", "credit_note.refund_failure"])
      end
    end

    context "when event_types is explicitly set to null" do
      let(:update_params) { {event_types: nil} }

      it "nullifies event_types" do
        result = update_service.call

        expect(result).to be_success
        expect(result.webhook_endpoint.event_types).to eq(nil)
      end
    end
  end
end
