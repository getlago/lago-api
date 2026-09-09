# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Orders::CreatedService do
  subject(:webhook_service) { described_class.new(object: order) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:order) { create(:order, organization:, customer:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "order.created", "order", {
      "lago_id" => String,
      "number" => String,
      "status" => "created",
      "order_type" => String,
      "lago_order_form_id" => String,
      "created_at" => String
    }

    it "omits the billing snapshot" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload
      expect(payload["order"]).not_to have_key("billing_snapshot")
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
