# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::BaseService do
  subject(:webhook_service) { WebhooksSpec::DummyClass.new(object:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, organization:) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:object) { invoice }
  let(:previous_webhook) { nil }

  describe ".call" do
    it "creates a pending webhook" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first

      aggregate_failures do
        expect(webhook.status).to eq("pending")
        expect(webhook.retries).to be_zero
        expect(webhook.webhook_type).to eq("dummy.test")
        expect(webhook.endpoint).to eq(webhook.webhook_endpoint.webhook_url)
        expect(webhook.object_id).to eq(invoice.id)
        expect(webhook.object_type).to eq("Invoice")
        expect(webhook.http_status).to be_nil
        expect(webhook.response).to be_nil
        expect(webhook.payload.keys).to eq %w[webhook_type object_type organization_id dummy]
      end
    end

    context "when organization has one webhook endpoint" do
      it "enqueues one http job" do
        webhook_service.call

        expect(SendHttpWebhookJob).to have_been_enqueued.once
      end
    end

    context "when organization has 2 webhook endpoints" do
      it "calls 2 webhooks" do
        create(:webhook_endpoint, organization:)
        object.reload
        webhook_service.call

        expect(SendHttpWebhookJob).to have_been_enqueued.twice
      end
    end

    context "without webhook endpoint" do
      let(:organization) { create(:organization) }

      before do
        organization.webhook_endpoints.destroy_all
      end

      it "does not create the webhook model" do
        webhook_service.call

        expect(SendHttpWebhookJob).not_to have_been_enqueued
        expect(Webhook.where(object: invoice)).not_to exist
      end
    end
  end
end

module WebhooksSpec
  class DummyClass < Webhooks::BaseService
    def current_organization
      @current_organization ||= object.organization
    end

    def object_serializer
      ::V1::InvoiceSerializer.new(
        object,
        root_name: "invoice"
      )
    end

    def webhook_type
      "dummy.test"
    end

    def object_type
      "dummy"
    end
  end
end
