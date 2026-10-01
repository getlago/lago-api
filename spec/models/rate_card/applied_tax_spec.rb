# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCard::AppliedTax do
  subject(:applied_tax) { build(:rate_card_applied_tax) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(applied_tax).to belong_to(:rate_card)
      expect(applied_tax).to belong_to(:tax)
      expect(applied_tax).to belong_to(:organization)
    end
  end

  describe "Scopes" do
    describe ".listed" do
      subject(:listed) { described_class.listed }

      let(:rate_card) { create(:rate_card) }
      let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
      let!(:older) { create(:rate_card_applied_tax, rate_card:, created_at: created_at - 1.second) }
      let!(:tied) { create_list(:rate_card_applied_tax, 2, rate_card:, created_at:) }

      # A discarded tax whose link was kept.
      before { create(:rate_card_applied_tax, rate_card:, created_at:).tax.discard! }

      it "leaves out the links of discarded taxes" do
        expect(listed).to match_array([older, *tied])
      end

      it "ends with the keyset order" do
        expect(listed.to_sql).to end_with(%(ORDER BY "rate_cards_taxes"."created_at" DESC, "rate_cards_taxes"."id" DESC))
      end

      it "orders ties by id" do
        expect(listed.map(&:id)).to eq([*tied.map(&:id).sort.reverse, older.id])
      end

      it "preloads the taxes in their own query" do
        queries = capture_sql { listed.to_a }
        selected = queries.first[/\ASELECT (.+?) FROM "rate_cards_taxes" INNER JOIN "taxes"/, 1]

        expect(queries.size).to eq(2)
        expect(selected.split(", ")).to all(start_with(%("rate_cards_taxes".)))
        expect(queries.second).to match(/\ASELECT .+ FROM "taxes" WHERE/)
        expect(listed).to all(satisfy { it.association(:tax).loaded? })
      end
    end
  end
end
