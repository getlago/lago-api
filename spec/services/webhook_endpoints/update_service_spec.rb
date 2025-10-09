# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::UpdateService do
  subject(:update_service) { described_class.new(id: webhook_endpoint.id, organization:, params: update_params) }

  let(:organization) { create(:organization) }
  let!(:webhook_endpoint) { create(:webhook_endpoint, organization:) }
  let(:update_params) do
    {
      webhook_url: "http://foo.bar",
      signature_algo: "hmac"
    }
  end

  describe ".call" do
    it "updates the webhook endpoint" do
      result = update_service.call

      aggregate_failures do
        expect(result).to be_success
        expect(result.webhook_endpoint.webhook_url).to eq("http://foo.bar")
        expect(result.webhook_endpoint.signature_algo).to eq("hmac")
      end
    end

    context "when webhook endpoint does not exist" do
      let(:webhook_endpoint) { instance_double(WebhookEndpoint, id: "123456") }

      it "returns a not found error" do
        result = update_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.message).to eq("webhook_endpoint_not_found")
        end
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

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error.class).to eq(BaseService::ValidationFailure)
        end
      end
    end
  end
end
