# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardTaxesQuery do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {rate_card_id: rate_card.id} }

  let(:rate_card) { create(:rate_card, organization:) }
  let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
  let!(:older) { create(:rate_card_applied_tax, rate_card:, created_at: created_at - 1.second) }
  let!(:newer) { create(:rate_card_applied_tax, rate_card:, created_at:) }
  let!(:sibling) { create(:rate_card_applied_tax, rate_card: create(:rate_card, organization:)) }
  let!(:foreign) { create(:rate_card_applied_tax) }

  it "lists the taxes of the rate card, newest first" do
    expect(result.applied_taxes).to eq([newer, older])
  end

  it "preloads the taxes" do
    expect(result.applied_taxes.to_a).to all(satisfy { it.association(:tax).loaded? })
  end

  context "without a rate_card_id filter" do
    let(:filters) { {} }

    it "lists the taxes of every rate card of the organization" do
      expect(result.applied_taxes).to match_array([newer, older, sibling])
    end
  end

  context "with a rate card of another organization" do
    let(:filters) { {rate_card_id: foreign.rate_card_id} }

    it "lists nothing" do
      expect(result.applied_taxes).to be_empty
    end
  end

  # Discarded directly: Taxes::DestroyService would delete the link as well.
  context "with a discarded tax" do
    before { create(:rate_card_applied_tax, rate_card:, created_at: created_at + 1.second).tax.discard! }

    it "leaves it out" do
      expect(result.applied_taxes).to eq([newer, older])
    end
  end

  context "with cursor pagination" do
    let(:pagination) { CursorPagination::Cursor.new(table: "rate_cards_taxes", limit: 1) }

    it "pages the taxes of the rate card" do
      page = CursorPagination::Page.new(records: result.applied_taxes, cursor: pagination)

      expect(page.records).to eq([newer])
      expect(page.meta[:next_cursor]).to be_present
    end
  end
end
