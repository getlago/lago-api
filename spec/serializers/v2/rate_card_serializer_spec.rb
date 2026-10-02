# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardSerializer do
  subject(:payload) { described_class.new(rate_card, root_name: "rate_card", includes:).serialize }

  let(:rate_card) { create(:rate_card) }
  let(:includes) { %i[active_rate rates deleted_at] }
  let!(:effective_rate) { create(:rate_card_rate, organization: rate_card.organization, rate_card:, effective_from: 1.day.ago.beginning_of_day) }

  it "renders deleted_at on the card and on the rates it embeds" do
    expect(payload).to include(deleted_at: nil)
    expect(payload[:active_rate]).to include(deleted_at: nil)
    expect(payload[:rates].sole).to include(deleted_at: nil)
  end

  # As outside REST, where no caller passes deleted_at.
  context "without deleted_at" do
    let(:includes) { %i[active_rate rates counts] }

    it "renders deleted_at nowhere" do
      expect(payload).not_to have_key(:deleted_at)
      expect(payload[:active_rate]).not_to have_key(:deleted_at)
      expect(payload[:rates].sole).not_to have_key(:deleted_at)
    end
  end

  # Appended after the effective rate, in reverse effective_from order.
  context "with pending rates created out of order" do
    let(:includes) { %i[rates] }
    let!(:later_rate) { create(:rate_card_rate, organization: rate_card.organization, rate_card:, effective_from: 2.months.from_now.beginning_of_day) }
    let!(:sooner_rate) { create(:rate_card_rate, organization: rate_card.organization, rate_card:, effective_from: 1.month.from_now.beginning_of_day) }

    it "lists the rates latest effective_from first" do
      expect(payload[:rates].map { it.values_at(:lago_id, :status) }).to eq(
        [[later_rate.id, "pending"], [sooner_rate.id, "pending"], [effective_rate.id, "active"]]
      )
    end

    it "derives the statuses from the loaded rates once they are all effective" do
      travel_to(3.months.from_now) do
        queries = capture_sql { payload }

        expect(payload[:rates].pluck(:status)).to eq(%w[active terminated terminated])
        # A rate whose siblings are not loaded checks them with one EXISTS each.
        expect(queries.grep(/\ASELECT 1 AS one FROM "rate_card_rates"/)).to be_empty
      end
    end
  end

  context "with taxes sharing created_at" do
    let(:includes) { %i[taxes] }
    let(:created_at) { Time.zone.parse("2026-09-28T10:00:00.000001Z") }
    # Oldest first, the reverse of the listed order.
    let!(:applied_taxes) { [1, 0, 0].map { create(:rate_card_applied_tax, rate_card:, created_at: created_at - it.seconds) } }

    it "lists the taxes newest first, ties ordered by id" do
      expected = applied_taxes.sort_by { [it.created_at, it.id] }.reverse.map(&:tax_id)

      expect(payload[:taxes].pluck(:lago_id)).to eq(expected)
    end
  end

  # What the activity log passes, with the rates left out.
  context "with taxes and counts" do
    let(:includes) { %i[taxes counts] }
    let!(:applied_tax) { create(:rate_card_applied_tax, rate_card:) }

    it "renders the rates count and each tax in the V1 shape, with its zero counts" do
      expect(payload[:rates_count]).to eq(1)
      expect(payload[:taxes]).to eq([V1::TaxSerializer.new(applied_tax.tax).serialize])
    end
  end

  # What a v2 show passes with expand[]=taxes.
  context "with taxes and deleted_at" do
    let(:includes) { %i[taxes deleted_at] }
    let!(:applied_tax) { create(:rate_card_applied_tax, rate_card:) }

    it "renders deleted_at on each tax, and no count" do
      expect(payload).not_to have_key(:rates_count)
      expect(payload[:taxes].sole).to include(lago_id: applied_tax.tax_id, deleted_at: nil)
      expect(payload[:taxes].sole.keys & V2::TaxSerializer::ZERO_COUNTS.keys).to be_empty
    end
  end
end
