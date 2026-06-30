# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::DestroyService do
  subject(:result) { described_class.call(rate_card:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }

  before do
    create(:rate_card_rate, organization:, rate_card:) if rate_card
  end

  it "soft deletes the card and its rates" do
    rate_ids = rate_card.rates.ids

    expect(result).to be_success
    expect(rate_card.reload).to be_discarded
    expect(RateCardRate.with_discarded.where(id: rate_ids).map(&:discarded?)).to all(be(true))
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("rate_card.deleted").after_commit.with(rate_card)
  end

  context "when rate_card is nil" do
    let(:rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end
end
