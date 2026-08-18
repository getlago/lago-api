# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Quotes::CreatedService do
  subject(:webhook_service) { described_class.new(object: quote_version) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) { create(:quote_version, organization:, quote:, content: "<p>Terms</p>") }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "quote.created", "quote", {
      "lago_id" => String,
      "number" => String,
      "order_type" => String,
      "lago_customer_id" => String,
      "lago_organization_id" => String,
      "version" => Hash,
      "created_at" => String,
      "updated_at" => String
    }

    it "omits the heavy and internal attributes" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload
      expect(payload["quote"]).not_to have_key("owners")
      expect(payload["quote"]).not_to have_key("current_version")
      expect(payload["quote"]["version"]).not_to have_key("content")
      expect(payload["quote"]["version"]).not_to have_key("billing_items")
    end
  end

  describe ".call when the feature is unavailable" do
    context "when the license is not premium" do
      it "does not create a webhook" do
        webhook_service.call

        expect(Webhook.count).to be_zero
      end
    end

    context "when the order_forms feature flag is disabled", :premium do
      let(:organization) { create(:organization, webhook_url: "http://foo.bar") }

      it "does not create a webhook" do
        webhook_service.call

        expect(Webhook.count).to be_zero
      end
    end
  end
end
