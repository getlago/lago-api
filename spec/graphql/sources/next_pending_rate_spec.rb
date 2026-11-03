# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::NextPendingRate do
  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  describe "#fetch" do
    it "resolves the soonest rate after the given perspective" do
      source = described_class.new(1.month.ago.beginning_of_day)

      card = create(:rate_card, organization:, product:)
      create(:rate_card_rate, organization:, rate_card: card, effective_from: 2.months.ago.beginning_of_day)
      soonest = create(:rate_card_rate, organization:, rate_card: card, code: "soonest", effective_from: 1.month.from_now.beginning_of_day)
      create(:rate_card_rate, organization:, rate_card: card, code: "later", effective_from: 2.months.from_now.beginning_of_day)

      empty_card = create(:rate_card, organization:, product:)

      expect(source.fetch([card.id, empty_card.id])).to eq([soonest, nil])
    end

    it "resolves relative to the given perspective, not the live clock" do
      card = create(:rate_card, organization:, product:)
      nov_1 = create(:rate_card_rate, organization:, rate_card: card, code: "nov-1", effective_from: Time.zone.parse("2026-11-01"))
      nov_16 = create(:rate_card_rate, organization:, rate_card: card, code: "nov-16", effective_from: Time.zone.parse("2026-11-16"))

      # Opened Oct 30th: the soonest rate not yet effective is Nov 1st.
      expect(described_class.new(Time.zone.parse("2026-10-30")).fetch([card.id])).to eq([nov_1])

      # Opened Nov 15th: Nov 1st is already effective, the soonest one left is Nov 16th.
      expect(described_class.new(Time.zone.parse("2026-11-15")).fetch([card.id])).to eq([nov_16])
    end
  end
end
