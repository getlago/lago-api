# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::SelectEffectiveService do
  subject(:selected_cards) { described_class.call!(contract_rate_cards:, date:).contract_rate_cards }

  let(:organization) { build_stubbed(:organization) }
  let(:contract) { build_stubbed(:contract, organization:) }
  let(:api_calls) { build_stubbed(:product, organization:) }
  let(:seats) { build_stubbed(:product, :fixed, organization:) }
  let(:api_calls_rate_card) { build_stubbed(:rate_card, organization:, product: api_calls) }
  let(:seats_rate_card) { build_stubbed(:rate_card, organization:, product: seats) }

  let(:api_calls_january) { card(api_calls_rate_card, Date.new(2027, 1, 1)) }
  let(:api_calls_february) { card(api_calls_rate_card, Date.new(2027, 2, 1)) }
  let(:seats_january) { card(seats_rate_card, Date.new(2027, 1, 10)) }
  let(:contract_rate_cards) { [api_calls_january, api_calls_february, seats_january] }
  let(:date) { Date.new(2027, 1, 15) }

  def card(rate_card, effective_date, contract: self.contract, created_at: Time.zone.parse("2026-12-01"), id: SecureRandom.uuid)
    build_stubbed(:contract_rate_card, organization:, contract:, rate_card:, effective_date:, created_at:, id:)
  end

  it "selects, for each product, the latest version that started on or before the date" do
    expect(selected_cards).to contain_exactly(api_calls_january, seats_january)
  end

  context "when the date is the later version's effective date" do
    let(:date) { Date.new(2027, 2, 1) }

    it "selects the later version" do
      expect(selected_cards).to contain_exactly(api_calls_february, seats_january)
    end
  end

  context "when every version of a product starts after the date" do
    let(:date) { Date.new(2027, 1, 5) }

    it "leaves that product out" do
      expect(selected_cards).to eq([api_calls_january])
    end
  end

  context "when the cards are not ordered" do
    let(:api_calls_december) { card(api_calls_rate_card, Date.new(2026, 12, 1)) }
    let(:contract_rate_cards) { [api_calls_february, api_calls_january, api_calls_december, seats_january] }

    it "still selects the effective version" do
      expect(selected_cards).to contain_exactly(api_calls_january, seats_january)
    end
  end

  context "with cards of the same product on different product filters" do
    let(:product_filter) { build_stubbed(:product_filter, organization:, product: api_calls) }
    let(:filtered_rate_card) { build_stubbed(:rate_card, organization:, product: api_calls, product_filter:) }
    let(:filtered_january) { card(filtered_rate_card, Date.new(2027, 1, 1)) }
    let(:contract_rate_cards) { [api_calls_january, filtered_january] }

    it "selects a version for each filter" do
      expect(selected_cards).to contain_exactly(api_calls_january, filtered_january)
    end
  end

  context "with cards of the same product on different contracts" do
    let(:other_contract) { build_stubbed(:contract, organization:) }
    let(:other_contract_january) { card(api_calls_rate_card, Date.new(2027, 1, 1), contract: other_contract) }
    let(:contract_rate_cards) { [api_calls_january, other_contract_january] }

    it "selects a version for each contract" do
      expect(selected_cards).to contain_exactly(api_calls_january, other_contract_january)
    end
  end

  context "with two versions starting on the same day" do
    let(:earlier) { card(api_calls_rate_card, Date.new(2027, 1, 1), created_at: Time.zone.parse("2026-12-01")) }
    let(:later) { card(api_calls_rate_card, Date.new(2027, 1, 1), created_at: Time.zone.parse("2026-12-02")) }
    let(:contract_rate_cards) { [later, earlier] }

    it "selects the one created last" do
      expect(selected_cards).to eq([later])
    end

    context "when they were also created at the same time" do
      let(:earlier) { card(api_calls_rate_card, Date.new(2027, 1, 1), id: "00000000-0000-0000-0000-000000000001") }
      let(:later) { card(api_calls_rate_card, Date.new(2027, 1, 1), id: "00000000-0000-0000-0000-000000000002") }

      it "selects the one with the greater id" do
        expect(selected_cards).to eq([later])
      end
    end
  end

  context "without cards" do
    let(:contract_rate_cards) { [] }

    it "selects nothing" do
      expect(selected_cards).to eq([])
    end
  end
end
