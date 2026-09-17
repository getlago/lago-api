# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Quotes::VoidedService do
  subject(:webhook_service) { described_class.new(object: quote_version) }

  let(:organization) { create(:organization, webhook_url: "http://foo.bar", feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) { create(:quote_version, :voided, organization:, quote:) }

  describe ".call", :premium do
    it_behaves_like "creates webhook", "quote.voided", "quote", {
      "lago_id" => String,
      "number" => String,
      "version" => Hash
    }

    it "carries the voided version state" do
      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload
      expect(payload["quote"]["version"]).to include(
        "lago_id" => quote_version.id,
        "status" => "voided",
        "void_reason" => "manual",
        "voided_at" => String
      )
    end

    context "when the version was superseded by a clone" do
      let(:quote_version) do
        create(:quote_version, :voided, organization:, quote:, void_reason: :superseded)
      end

      # The replacement draft is created in the same transaction as the void, so a payload
      # built from the quote's current version would describe the wrong one.
      it "still describes the superseded version, not the replacement draft" do
        create(:quote_version, organization:, quote:, sequential_id: quote_version.sequential_id + 1)

        webhook_service.call

        payload = Webhook.order(created_at: :desc).first.payload
        expect(payload["quote"]["version"]).to include(
          "lago_id" => quote_version.id,
          "status" => "voided",
          "void_reason" => "superseded"
        )
      end
    end
  end
end
