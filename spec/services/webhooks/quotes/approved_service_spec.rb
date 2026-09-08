# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Quotes::ApprovedService do
  subject(:webhook_service) { described_class.new(object: quote_version) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) { create(:quote_version, :approved, organization:, quote:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "quote.approved", "quote", {
      "lago_id" => String,
      "number" => String,
      "version" => Hash
    }

    it "carries the approved version state" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload
      expect(payload["quote"]["version"]).to include(
        "lago_id" => quote_version.id,
        "status" => "approved",
        "approved_at" => String
      )
    end
  end
end
