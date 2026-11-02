# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::PendingRate do
  subject(:source) { described_class.new }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  describe "#fetch" do
    it "resolves the soonest pending rate of each card" do
      card = create(:rate_card, organization:, product:)
      create(:rate_card_rate, organization:, rate_card: card, effective_from: 1.month.ago.beginning_of_day)
      soonest = create(:rate_card_rate, organization:, rate_card: card, code: "soonest", effective_from: 1.month.from_now.beginning_of_day)
      create(:rate_card_rate, organization:, rate_card: card, code: "later", effective_from: 2.months.from_now.beginning_of_day)

      empty_card = create(:rate_card, organization:, product:)

      expect(source.fetch([card.id, empty_card.id])).to eq([soonest, nil])
    end
  end
end
