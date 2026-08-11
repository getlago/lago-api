# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Quotes::VoidedService do
  subject(:webhook_service) { described_class.new(object: quote) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }

  before { create(:quote_version, :voided, organization:, quote:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "quote.voided", "quote", {
      "lago_id" => String,
      "number" => String,
      "current_version" => Hash
    }

    it "carries the voided version state" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload
      expect(payload["quote"]["current_version"]).to include(
        "status" => "voided",
        "void_reason" => "manual",
        "voided_at" => String
      )
    end
  end
end
