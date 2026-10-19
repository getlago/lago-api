# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCardRates::CreatedService do
  let(:organization) { create(:organization) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:) }

  before { allow(rate_card_rate.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe Webhooks::RateCardRates::CreatedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it_behaves_like "creates webhook", "rate_card_rate.created", "rate_card_rate", {"code" => String}

    it "includes the rate card code in the standalone webhook object" do
      create(:webhook_endpoint, organization:)

      webhook_service.call

      payload = Webhook.order(created_at: :desc).first.payload
      expect(payload.fetch("rate_card_rate")).to include("rate_card_code" => rate_card_rate.rate_card.code)
    end
  end

  describe Webhooks::RateCardRates::UpdatedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it_behaves_like "creates webhook", "rate_card_rate.updated", "rate_card_rate", {"code" => String}
  end

  describe Webhooks::RateCardRates::DeletedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it_behaves_like "creates webhook", "rate_card_rate.deleted", "rate_card_rate", {"code" => String}

    it "includes its own parent code when serialized after the rate and card are discarded" do
      rate_card = rate_card_rate.rate_card
      other_rate_card = create(:rate_card, organization:, code: "other-card")
      create(:webhook_endpoint, organization:)
      rate_card_rate.discard
      rate_card.discard
      delayed_rate = RateCardRate.with_discarded.find(rate_card_rate.id)
      allow(delayed_rate.organization).to receive(:product_catalog_enabled?).and_return(true)

      described_class.new(object: delayed_rate).call

      payload = Webhook.order(created_at: :desc).first.payload.fetch("rate_card_rate")
      expect(payload).to include("rate_card_code" => rate_card.code)
      expect(payload).not_to include("rate_card_code" => other_rate_card.code)
    end
  end
end
