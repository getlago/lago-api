# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractRateCardsController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, currency: "EUR") }
  let(:contract) { create(:contract, :pending, organization:, customer:) }
  let(:rate_card) { create(:rate_card, organization:, currency: "EUR") }

  describe "POST /api/v2/contracts/:external_id/applied_rate_cards" do
    subject { post_with_token(organization, "/api/v2/contracts/#{external_id}/applied_rate_cards", {applied_rate_card: create_params}) }

    let(:external_id) { contract.external_id }
    let(:create_params) { {rate_card_code: rate_card.code, units: "10"} }

    include_examples "requires API permission", "contract_rate_card", "write"

    it "attaches the rate card to the contract with a default rate phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:applied_rate_card][:lago_id]).to be_present
      expect(json[:applied_rate_card][:external_contract_id]).to eq(contract.external_id)
      expect(json[:applied_rate_card][:rate_card_code]).to eq(rate_card.code)
      expect(json[:applied_rate_card][:rate_phases_count]).to eq(1)
    end

    context "when the contract does not exist" do
      let(:external_id) { "unknown" }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("contract")
      end
    end

    context "when the rate card does not exist" do
      let(:create_params) { {rate_card_code: "unknown"} }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("rate_card")
      end
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, organization:, customer:) }

      it "returns an unprocessable entity error" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id/applied_rate_cards" do
    subject { get_with_token(organization, "/api/v2/contracts/#{external_id}/applied_rate_cards") }

    let(:external_id) { contract.external_id }
    let!(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

    before { create(:contract_rate_card, organization:) }

    include_examples "requires API permission", "contract_rate_card", "read"

    it "returns the contract's applied rate cards" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:applied_rate_cards].map { it[:lago_id] }).to eq([contract_rate_card.id])
    end
  end

  describe "GET /api/v2/contracts/:external_id/applied_rate_cards/:code" do
    subject { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards/#{code}") }

    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
    let(:code) { rate_card.code }

    include_examples "requires API permission", "contract_rate_card", "read"

    it "returns the applied rate card" do
      contract_rate_card
      subject

      expect(response).to have_http_status(:success)
      expect(json[:applied_rate_card][:lago_id]).to eq(contract_rate_card.id)
    end

    context "when the card does not exist" do
      let(:code) { "unknown" }

      it "returns a not found error" do
        subject
        expect(response).to be_not_found_error("applied_rate_card")
      end
    end
  end

  describe "PUT /api/v2/contracts/:external_id/applied_rate_cards/:code" do
    subject { put_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards/#{rate_card.code}", {applied_rate_card: {units: "42"}}) }

    let!(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:, units: 1) }

    include_examples "requires API permission", "contract_rate_card", "write"

    it "updates the units" do
      subject

      expect(response).to have_http_status(:success)
      expect(contract_rate_card.reload.units).to eq(42)
    end
  end

  describe "DELETE /api/v2/contracts/:external_id/applied_rate_cards/:code" do
    subject { delete_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards/#{rate_card.code}") }

    let!(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

    include_examples "requires API permission", "contract_rate_card", "write"

    it "discards the applied rate card" do
      subject

      expect(response).to have_http_status(:success)
      expect(contract_rate_card.reload.discarded?).to be(true)
    end
  end
end
