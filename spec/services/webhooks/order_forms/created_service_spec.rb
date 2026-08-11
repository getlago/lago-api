# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::OrderForms::CreatedService do
  subject(:webhook_service) { described_class.new(object: order_form) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:order_form) { create(:order_form, organization:, customer:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "order_form.created", "order_form", {
      "lago_id" => String,
      "number" => String,
      "status" => "generated",
      "lago_quote_id" => String,
      "lago_quote_version_id" => String,
      "lago_customer_id" => String,
      "created_at" => String
    }
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
