# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::ActiveRate do
  subject(:source) { described_class.new }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  describe "#fetch" do
    it "resolves the latest effective rate of each card" do
      card = create(:rate_card, organization:, product:)
      create(:rate_card_rate, organization:, rate_card: card, effective_from: 2.months.ago.beginning_of_day)
      active = create(:rate_card_rate, organization:, rate_card: card, code: "newer", effective_from: 1.month.ago.beginning_of_day)
      create(:rate_card_rate, organization:, rate_card: card, code: "pending", effective_from: 1.month.from_now.beginning_of_day)

      empty_card = create(:rate_card, organization:, product:)

      expect(source.fetch([card.id, empty_card.id])).to eq([active, nil])
    end
  end
end
