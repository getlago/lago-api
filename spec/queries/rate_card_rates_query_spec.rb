# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRatesQuery do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:rate_card) { create(:rate_card, organization:) }
  let!(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day) }

  before { create(:rate_card_rate, organization:) }

  it "preloads the card timeline so statuses derive without extra queries" do
    create(:rate_card_rate, organization:, rate_card:, code: "newer", effective_from: 1.hour.ago)

    loaded = result.rate_card_rates.to_a
    statuses = loaded.to_h { [it.code, it.status] }

    expect(loaded).to all(satisfy { it.association(:rate_card).loaded? && it.rate_card.rates.loaded? })
    expect(statuses[rate.code]).to eq("terminated")
    expect(statuses["newer"]).to eq("active")
  end

  context "with a rate_card_id filter" do
    let(:filters) { {rate_card_id: rate_card.id} }

    it "returns only the rates of that rate card" do
      expect(result.rate_card_rates).to eq([rate])
    end
  end

  context "with pagination" do
    let(:filters) { {rate_card_id: rate_card.id} }
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.rate_card_rates.count).to eq(1)
    end
  end
end
