# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::RateCards::CreatedService do
  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  before { allow(rate_card.organization).to receive(:product_catalog_enabled?).and_return(true) }

  describe Webhooks::RateCards::CreatedService do
    subject(:webhook_service) { described_class.new(object: rate_card) }

    it_behaves_like "creates webhook", "rate_card.created", "rate_card", {"code" => String}
  end

  describe Webhooks::RateCards::UpdatedService do
    subject(:webhook_service) { described_class.new(object: rate_card) }

    it_behaves_like "creates webhook", "rate_card.updated", "rate_card", {"code" => String}
  end

  describe Webhooks::RateCards::DeletedService do
    subject(:webhook_service) { described_class.new(object: rate_card) }

    it_behaves_like "creates webhook", "rate_card.deleted", "rate_card", {"code" => String}
  end
end
