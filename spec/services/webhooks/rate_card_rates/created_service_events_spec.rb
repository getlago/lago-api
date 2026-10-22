# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCardRates::CreatedService do
  let(:organization) { create(:organization) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:) }
  let(:other_rate_card) { create(:rate_card, organization:, code: "other-card") }

  before do
    allow(rate_card_rate.organization).to receive(:product_catalog_enabled?).and_return(true)
    create(:webhook_endpoint, organization:)
  end

  describe Webhooks::RateCardRates::CreatedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it "serializes every rate field and its parent card code" do
      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "rate_card_rate.created",
        "object_type" => "rate_card_rate",
        "organization_id" => organization.id,
        "rate_card_rate" => {
          "lago_id" => rate_card_rate.id,
          "code" => rate_card_rate.code,
          "rate_card_code" => rate_card_rate.rate_card.code,
          "effective_from" => rate_card_rate.effective_from.iso8601,
          "status" => "active",
          "rate_model" => "standard",
          "rate_properties" => {"amount" => "10"},
          "min_amount_cents" => 0,
          "billing_interval_count" => 1,
          "billing_interval_unit" => "month",
          "applied_pricing_unit_conversion_rate" => nil,
          "created_at" => rate_card_rate.created_at.iso8601,
          "updated_at" => rate_card_rate.updated_at.iso8601,
          "deleted_at" => nil
        }
      )
    end
  end

  describe Webhooks::RateCardRates::UpdatedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it "serializes the changed rate state in the full webhook payload" do
      rate_card_rate.update!(rate_properties: {"amount" => "27.50"}, min_amount_cents: 250)

      webhook_service.call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "rate_card_rate.updated",
        "object_type" => "rate_card_rate",
        "organization_id" => organization.id,
        "rate_card_rate" => {
          "lago_id" => rate_card_rate.id,
          "code" => rate_card_rate.code,
          "rate_card_code" => rate_card_rate.rate_card.code,
          "effective_from" => rate_card_rate.effective_from.iso8601,
          "status" => "active",
          "rate_model" => "standard",
          "rate_properties" => {"amount" => "27.50"},
          "min_amount_cents" => 250,
          "billing_interval_count" => 1,
          "billing_interval_unit" => "month",
          "applied_pricing_unit_conversion_rate" => nil,
          "created_at" => rate_card_rate.created_at.iso8601,
          "updated_at" => rate_card_rate.updated_at.iso8601,
          "deleted_at" => nil
        }
      )
    end
  end

  describe Webhooks::RateCardRates::DeletedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it "serializes the full rate and retains its parent code after rate and card discard" do
      rate_card = rate_card_rate.rate_card
      rate_card_rate.discard
      rate_card.discard
      delayed_rate = RateCardRate.with_discarded.find(rate_card_rate.id)
      allow(delayed_rate.organization).to receive(:product_catalog_enabled?).and_return(true)

      described_class.new(object: delayed_rate).call

      expect(Webhook.order(created_at: :desc).first.payload).to eq(
        "webhook_type" => "rate_card_rate.deleted",
        "object_type" => "rate_card_rate",
        "organization_id" => organization.id,
        "rate_card_rate" => {
          "lago_id" => delayed_rate.id,
          "code" => delayed_rate.code,
          "rate_card_code" => rate_card.code,
          "effective_from" => delayed_rate.effective_from.iso8601,
          "status" => "active",
          "rate_model" => "standard",
          "rate_properties" => {"amount" => "10"},
          "min_amount_cents" => 0,
          "billing_interval_count" => 1,
          "billing_interval_unit" => "month",
          "applied_pricing_unit_conversion_rate" => nil,
          "created_at" => delayed_rate.created_at.iso8601,
          "updated_at" => delayed_rate.updated_at.iso8601,
          "deleted_at" => delayed_rate.deleted_at.iso8601
        }
      )
      expect(Webhook.order(created_at: :desc).first.payload.dig("rate_card_rate", "rate_card_code")).not_to eq(other_rate_card.code)
    end
  end
end
