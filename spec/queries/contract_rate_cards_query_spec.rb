# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCardsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:, order:)
  end

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }
  let(:order) { nil }

  let(:contract) { create(:contract, organization:) }
  let!(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

  before { create(:contract_rate_card, organization:) }

  it "returns the organization's contract rate cards" do
    expect(result).to be_success
    expect(result.contract_rate_cards.count).to eq(2)
  end

  it "excludes ended cards" do
    ended = create(:contract_rate_card, organization:, contract:, effective_date: 3.days.ago, ended_date: 1.day.ago)

    expect(result.contract_rate_cards).not_to include(ended)
    expect(result.contract_rate_cards.count).to eq(2)
  end

  context "with a contract_id filter" do
    let(:filters) { {contract_id: contract.id} }

    it "returns only that contract's cards" do
      expect(result.contract_rate_cards.to_a).to eq([contract_rate_card])
    end
  end

  context "with an external_id filter" do
    let(:filters) { {external_id: contract.external_id} }

    it "returns only that contract's cards" do
      expect(result.contract_rate_cards.to_a).to eq([contract_rate_card])
    end
  end

  context "with several cards on the contract" do
    let(:filters) { {contract_id: contract.id} }
    let!(:scheduled) { create(:contract_rate_card, organization:, contract:, effective_date: 5.days.from_now.to_date) }
    let!(:earlier) { create(:contract_rate_card, organization:, contract:, effective_date: 10.days.ago.to_date) }

    it "orders them by effective date" do
      expect(result.contract_rate_cards.to_a).to eq([earlier, contract_rate_card, scheduled])
    end
  end

  context "when ordering by product category" do
    let(:order) { :product_category }
    let(:filters) { {contract_id: contract.id} }
    let(:product) { create(:product, organization:) }
    let(:contract_rate_card) { card_for(create(:product, :standalone, organization:)) }
    let!(:later_card) { card_for(product, effective_date: 5.days.from_now.to_date) }
    let!(:earlier_card) { card_for(product, effective_date: 10.days.ago.to_date) }

    def card_for(product, **attributes)
      create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:), **attributes)
    end

    it "groups by category, standalone products last, then by effective date" do
      expect(result.contract_rate_cards.to_a).to eq([earlier_card, later_card, contract_rate_card])
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.contract_rate_cards.count).to eq(1)
      expect(result.contract_rate_cards.current_page).to eq(1)
    end
  end
end
