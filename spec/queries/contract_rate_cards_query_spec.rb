# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCardsQuery do
  subject(:result) do
    described_class.call(organization:, pagination:, filters:)
  end

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:contract) { create(:contract, organization:) }
  let!(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

  before { create(:contract_rate_card, organization:) }

  it "returns the organization's contract rate cards" do
    expect(result).to be_success
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

  context "with pagination" do
    let(:pagination) { {page: 1, limit: 1} }

    it "paginates the results" do
      expect(result.contract_rate_cards.count).to eq(1)
      expect(result.contract_rate_cards.current_page).to eq(1)
    end
  end
end
