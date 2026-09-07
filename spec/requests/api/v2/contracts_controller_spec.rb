# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractsController do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, :product_catalog, organization:) }

  describe "POST /api/v2/contracts" do
    subject { post_with_token(organization, "/api/v2/contracts", {contract: create_params}) }

    let(:create_params) do
      {
        external_customer_id: customer.external_id,
        external_id: "contract-1",
        plan_code: plan.code
      }
    end

    include_examples "requires API permission", "contract", "write"

    it "creates the contract and returns it with its materialized rate cards" do
      rate_card = create(:rate_card, organization:)
      create(:plan_rate_card, organization:, plan:, rate_card:, units: 2)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:external_id]).to eq("contract-1")
      expect(json[:contract][:plan_code]).to eq(plan.code)
      expect(json[:contract][:status]).to eq("active")
      expect(json[:contract][:applied_rate_cards_count]).to eq(1)
      expect(json[:contract][:applied_rate_cards].sole[:rate_card_code]).to eq(rate_card.code)
    end

    context "without a plan" do
      let(:create_params) { {external_customer_id: customer.external_id, external_id: "contract-1"} }

      it "creates a plan-less contract" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:plan_code]).to be_nil
        expect(json[:contract][:applied_rate_cards]).to be_empty
      end
    end

    context "when the customer does not exist" do
      let(:create_params) { super().merge(external_customer_id: "unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("customer")
      end
    end

    context "when a live contract already uses the external id" do
      before { create(:contract, organization:, customer:, external_id: "contract-1") }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :external_id)).to eq(["value_already_exists"])
      end
    end
  end

  describe "GET /api/v2/contracts" do
    subject { get_with_token(organization, "/api/v2/contracts") }

    let!(:contract) { create(:contract, organization:, customer:, plan:) }

    include_examples "requires API permission", "contract", "read"

    it "lists active contracts with their card counts" do
      create(:contract_rate_card, organization:, contract:)
      # An ended attachment must not inflate the grouped count.
      create(:contract_rate_card, organization:, contract:, effective_date: 10.days.ago.to_date, ended_date: 1.day.ago.to_date)

      subject

      expect(response).to have_http_status(:success)
      result = json[:contracts].sole
      expect(result[:lago_id]).to eq(contract.id)
      expect(result[:applied_rate_cards_count]).to eq(1)
    end

    context "with a pending contract" do
      let!(:pending_contract) { create(:contract, :pending, organization:, customer:) }

      it "lists only active contracts by default" do
        subject

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([contract.id])
      end

      it "lists pending contracts when the status filter asks for them" do
        get_with_token(organization, "/api/v2/contracts?status[]=pending")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([pending_contract.id])
      end

      it "accepts the scalar status form" do
        get_with_token(organization, "/api/v2/contracts?status=pending")

        expect(json[:contracts].map { |c| c[:lago_id] }).to eq([pending_contract.id])
      end
    end
  end

  describe "GET /api/v2/contracts/:external_id" do
    subject { get_with_token(organization, "/api/v2/contracts/#{contract.external_id}") }

    let!(:contract) { create(:contract, organization:, customer:, plan:) }

    include_examples "requires API permission", "contract", "read"

    it "returns the contract with its rate cards" do
      card = create(:contract_rate_card, organization:, contract:)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:contract][:lago_id]).to eq(contract.id)
      expect(json[:contract][:applied_rate_cards].sole[:lago_id]).to eq(card.id)
    end

    context "when the external id contains a dot" do
      let(:contract) { create(:contract, organization:, customer:, external_id: "contract.2026-01") }

      it "matches the full id instead of truncating at the format separator" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:external_id]).to eq("contract.2026-01")
      end
    end

    context "with an unknown status filter value" do
      it "falls back to the active contract instead of raising on the enum cast" do
        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}?status=bogus")

        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
      end
    end

    context "when the contract is pending" do
      let!(:contract) { create(:contract, :pending, organization:, customer:) }

      it "returns it without a status filter" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
        expect(json[:contract][:status]).to eq("pending")
      end
    end

    context "when reading a terminated contract by status" do
      let!(:contract) { create(:contract, :terminated, organization:, customer:) }

      it "returns it only with an explicit status filter" do
        subject
        expect(response).to be_not_found_error("contract")

        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}?status=terminated")
        expect(response).to have_http_status(:success)
        expect(json[:contract][:lago_id]).to eq(contract.id)
      end
    end

    context "when it does not exist" do
      subject { get_with_token(organization, "/api/v2/contracts/unknown") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("contract")
      end
    end
  end
end
