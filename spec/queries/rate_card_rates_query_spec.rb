# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRatesQuery do
  before_all do
    create_default(:billable_metric)
  end

  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let_it_be(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:rate_card) { create(:rate_card, organization:) }
  let!(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: 1.day.ago.beginning_of_day) }

  before { create(:rate_card_rate, organization:) }

  it "preloads the card timeline so statuses derive without extra queries" do
    create(:rate_card_rate, organization:, rate_card:, code: "newer", effective_from: 1.hour.ago)

    loaded = result.rate_card_rates.to_a
    statuses = loaded.to_h { [it.code, it.status] }
    queried_rate = loaded.find { it.id == rate.id }
    parent_card = queried_rate.rate_card

    expect(loaded).to all(satisfy { it.association(:rate_card).loaded? && it.rate_card.rates.loaded? })
    expect(parent_card.rates).to include(queried_rate)
    expect(queried_rate.association(:rate_card).target).to equal(parent_card)
    expect(statuses[rate.code]).to eq("terminated")
    expect(statuses["newer"]).to eq("active")
  end

  it "serializes rates and derives statuses without issuing additional queries" do
    create(:rate_card_rate, organization:, rate_card:, code: "newer", effective_from: 1.hour.ago)
    loaded = result.rate_card_rates.to_a
    queries = []
    subscriber = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      loaded.each { V2::RateCardRateSerializer.new(it, root_name: "rate").serialize }
    end

    expect(queries).to be_empty
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
