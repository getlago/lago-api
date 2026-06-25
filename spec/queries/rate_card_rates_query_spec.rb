# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRatesQuery do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:rate_card) { create(:rate_card, organization:) }
  let!(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: 1.day.ago) }

  before { create(:rate_card_rate, organization:) }

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
