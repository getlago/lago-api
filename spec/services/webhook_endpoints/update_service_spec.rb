# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::UpdateService do
  subject(:update_service) { described_class.new(id: webhook_endpoint.id, organization:, params: update_params) }

  include_context "with mocked security logger"

  let(:organization) { create(:organization) }
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

        it_behaves_like "does not produce a security log" do
          before { update_service.call }
        end
      end
    end

    context "when switching a jwt endpoint to standard_webhooks" do
      let(:update_params) { {name: "Updated Webhook", signature_algo: "standard_webhooks"} }

      it "returns a validation failure without the rollout flag, without changing the endpoint" do
        result = nil
        expect { result = update_service.call }.not_to change { webhook_endpoint.reload.attributes }

        expect(result).not_to be_success
        expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
        expect(result.error.meta).to eq(signature_algo: {allowed_values: %w[jwt hmac]})
      end

      context "when the organization has the standard_webhooks_signature flag" do
        let(:organization) { create(:organization, feature_flags: ["standard_webhooks_signature"]) }

        it "switches the endpoint to Standard Webhooks" do
          result = update_service.call

          expect(result).to be_success
          expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
          expect(webhook_endpoint.name).to eq("Updated Webhook")
        end

        it "creates one signing key with a whsec_ secret" do
          expect { update_service.call }.to change(webhook_endpoint.signing_keys, :count).from(0).to(1)

          expect(webhook_endpoint.signing_keys.sole.secret_key).to start_with("whsec_")
        end

        it "leaves one signing key when the switch runs twice" do
          described_class.call(id: webhook_endpoint.id, organization:, params: update_params)
          described_class.call(id: webhook_endpoint.id, organization:, params: update_params)

          expect(WebhookEndpointSigningKey.where(webhook_endpoint:).count).to eq(1)
        end

        context "when the endpoint is invalid" do
          let(:update_params) { {webhook_url: "foobar", signature_algo: "standard_webhooks"} }

          it "neither switches the endpoint nor creates a signing key" do
            result = nil
            expect { result = update_service.call }
              .to not_change { webhook_endpoint.reload.attributes }
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

          it "rolls back the switch" do
            result = nil
            expect { result = update_service.call }.not_to change { webhook_endpoint.reload.attributes }

            expect(result).not_to be_success
          end
        end

        context "with two threads switching the same endpoint", transaction: false do
          before do
            allow_any_instance_of(WebhookEndpoint).to receive(:save!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
              sleep(0.05)
              original.call(*args)
            end
          end

          it "serializes the switches and creates the signing key exactly once" do
            results = Concurrent::Array.new

            threads = Array.new(2) do
              Thread.new do
                results << described_class.call(id: webhook_endpoint.id, organization:, params: update_params)
              end
            end

            threads.each(&:join)

            expect(results.count(&:success?)).to eq(2)
            expect(WebhookEndpointSigningKey.where(webhook_endpoint:).count).to eq(1)
          end
        end
      end
    end

    context "when switching a standard_webhooks endpoint to jwt and back" do
      let(:organization) { create(:organization, feature_flags: ["standard_webhooks_signature"]) }
      let!(:webhook_endpoint) { create(:webhook_endpoint, :standard_webhooks, organization:) }
      let(:signing_key) { webhook_endpoint.signing_keys.sole }

      it "keeps the signing key and reuses it" do
        signing_key
        expect(described_class.call(id: webhook_endpoint.id, organization:, params: {signature_algo: "jwt"})).to be_success
        expect(webhook_endpoint.reload.signature_algo).to eq("jwt")
        expect(webhook_endpoint.signing_keys.pluck(:id)).to eq([signing_key.id])

        expect(described_class.call(id: webhook_endpoint.id, organization:, params: {signature_algo: "standard_webhooks"})).to be_success
        expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
        expect(webhook_endpoint.signing_keys.pluck(:id)).to eq([signing_key.id])
      end
    end

    context "when updating a jwt endpoint without changing its algorithm" do
      let(:update_params) { {name: "Updated Webhook"} }

      it "creates no signing key" do
        expect { update_service.call }.not_to change(WebhookEndpointSigningKey, :count)
      end
    end

    context "when the endpoint already uses standard_webhooks" do
      let!(:webhook_endpoint) do
        create(:webhook_endpoint, :legacy_signature_algo, organization:, name: "Original Webhook", signature_algo: "standard_webhooks")
      end
      let(:update_params) { {name: "Updated Webhook", signature_algo: "standard_webhooks"} }

      it "accepts the current algorithm again without the rollout flag" do
        result = update_service.call

        expect(result).to be_success
        expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
        expect(webhook_endpoint.name).to eq("Updated Webhook")
      end

      # The endpoint save writes nothing here, so only the row lock serializes the two key checks.
      context "with two threads re-sending it while the endpoint has no signing key", transaction: false do
        let(:update_params) { {signature_algo: "standard_webhooks"} }

        before do
          allow_any_instance_of(WebhookEndpointSigningKey).to receive(:save!).and_wrap_original do |original, **kwargs| # rubocop:disable RSpec/AnyInstance
            sleep(0.1)
            original.call(**kwargs)
          end
        end

        it "serializes the requests and creates the signing key exactly once" do
          results = Concurrent::Array.new

          threads = Array.new(2) do
            Thread.new do
              results << described_class.call(id: webhook_endpoint.id, organization:, params: update_params)
            end
          end

          threads.each(&:join)

          expect(results.count(&:success?)).to eq(2)
          expect(WebhookEndpointSigningKey.where(webhook_endpoint:).count).to eq(1)
        end
      end

      context "with a signing key" do
        before { create(:webhook_endpoint_signing_key, webhook_endpoint:) }

        it "keeps the same signing key" do
          signing_key_ids = webhook_endpoint.signing_keys.pluck(:id)

          expect(update_service.call).to be_success
          expect(webhook_endpoint.signing_keys.reload.pluck(:id)).to eq(signing_key_ids)
          expect(signing_key_ids.size).to eq(1)
        end
      end
    end

    context "when the organization has the product catalog" do
      let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
      let!(:webhook_endpoint) { create(:webhook_endpoint, :legacy_signature_algo, organization:, signature_algo: :jwt) }

      [[{}, "without a signature_algo"], [{signature_algo: "jwt"}, "when signature_algo is its current jwt"]].each do |algo_params, label|
        context label do
          let(:update_params) { {name: "Updated Webhook", **algo_params} }

          it "keeps the jwt algorithm the organization no longer allows" do
            result = update_service.call

            expect(result).to be_success
            expect(webhook_endpoint.reload.signature_algo).to eq("jwt")
            expect(webhook_endpoint.name).to eq("Updated Webhook")
          end
        end
      end

      context "when signature_algo is standard_webhooks" do
        let(:update_params) { {name: "Updated Webhook", signature_algo: "standard_webhooks"} }

        it "switches the endpoint without the rollout flag and creates one signing key" do
          expect { update_service.call }.to change(webhook_endpoint.signing_keys, :count).from(0).to(1)

          expect(webhook_endpoint.reload.signature_algo).to eq("standard_webhooks")
        end
      end

      context "when signature_algo is hmac" do
        let(:update_params) { {name: "Updated Webhook", signature_algo: "hmac"} }

        it "returns a validation failure allowing only standard_webhooks, without changing the endpoint" do
          result = nil
          expect { result = update_service.call }.not_to change { webhook_endpoint.reload.attributes }

          expect(result).not_to be_success
          expect(result.error.messages).to eq(signature_algo: ["value_is_invalid"])
          expect(result.error.meta).to eq(signature_algo: {allowed_values: ["standard_webhooks"]})
        end
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
