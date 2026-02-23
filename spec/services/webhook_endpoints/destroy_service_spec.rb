# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookEndpoints::DestroyService do
  subject(:destroy_service) { described_class.new(webhook_endpoint:) }

  include_context "with mocked security logger"

  context "when endpoint exists" do
    let!(:webhook_endpoint) { create(:webhook_endpoint) }

    it "destroys the webhook endpoint" do
      expect { destroy_service.call }.to change(WebhookEndpoint, :count).by(-1)
    end

    it "produces a security log" do
      destroy_service.call

      expect(security_logger).to have_received(:produce).with(
        organization: webhook_endpoint.organization,
        log_type: "webhook_endpoint",
        log_event: "webhook_endpoint.deleted",
        resources: {webhook_url: webhook_endpoint.webhook_url, signature_algo: "jwt"}
      )
    end
  end

  context "when webhook endpoint does not exist" do
    let(:webhook_endpoint) { nil }

    it "returns a not found error" do
      result = destroy_service.call

      expect(result).not_to be_success
      expect(result.error.message).to eq("webhook_endpoint_not_found")
    end

    it "does not produce a security log" do
      destroy_service.call

      expect(security_logger).not_to have_received(:produce)
    end
  end
end
