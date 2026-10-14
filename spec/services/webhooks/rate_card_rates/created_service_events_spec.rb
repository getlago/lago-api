# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCardRates::CreatedService do
  let(:organization) { create(:organization) }
  let(:rate_card_rate) { create(:rate_card_rate, organization:) }

  before { allow(rate_card_rate.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe Webhooks::RateCardRates::CreatedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it_behaves_like "creates webhook", "rate_card_rate.created", "rate_card_rate", {"code" => String}
  end

  describe Webhooks::RateCardRates::UpdatedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it_behaves_like "creates webhook", "rate_card_rate.updated", "rate_card_rate", {"code" => String}
  end

  describe Webhooks::RateCardRates::DeletedService do
    subject(:webhook_service) { described_class.new(object: rate_card_rate) }

    it_behaves_like "creates webhook", "rate_card_rate.deleted", "rate_card_rate", {"code" => String}
  end
end
