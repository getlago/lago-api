# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::ContractRateCards::RatePhasesController do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, :pending, organization:, customer:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

  let(:base_path) do
    "/api/v2/contracts/#{contract.external_id}/applied_rate_cards/#{rate_card.code}/rate_phases"
  end

  before do
    create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "default", position: 1)
  end

  describe "GET .../rate_phases" do
    subject { get_with_token(organization, base_path) }

    include_examples "requires API permission", "contract_rate_card", "read"

    it "lists the phases" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { it[:code] }).to eq(%w[default])
    end
  end

  describe "POST .../rate_phases" do
    subject { post_with_token(organization, base_path, {rate_phase: {code: "ramp", position: 1, billing_interval_cycle_count: 2}}) }

    include_examples "requires API permission", "contract_rate_card", "write"

    it "inserts a phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phase][:code]).to eq("ramp")
      expect(contract_rate_card.rate_phases.order(:position).map(&:code)).to eq(%w[ramp default])
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, organization:, customer:) }

      it "returns an unprocessable entity error" do
        subject
        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:rate_phase]).to eq(["contract_locked"])
      end
    end

    context "when a terminated contract reuses the external id" do
      before do
        create(:contract, :terminated, organization:, customer:, external_id: contract.external_id, started_at: 2.months.ago)
      end

      it "targets the live contract's card" do
        subject

        expect(response).to have_http_status(:success)
        expect(contract_rate_card.rate_phases.order(:position).map(&:code)).to eq(%w[ramp default])
      end
    end
  end

  describe "PUT .../rate_phases/:code" do
    subject { put_with_token(organization, "#{base_path}/default", {rate_phase: {name: "Renamed"}}) }

    include_examples "requires API permission", "contract_rate_card", "write"

    it "updates the phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phase][:name]).to eq("Renamed")
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, organization:, customer:) }

      it "returns a contract_locked error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:error_details][:rate_phase]).to eq(["contract_locked"])
      end
    end
  end

  describe "DELETE .../rate_phases/:code" do
    subject { delete_with_token(organization, "#{base_path}/#{phase_code}") }

    let(:phase_code) { "extra" }

    before { create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "extra", position: 2) }

    include_examples "requires API permission", "contract_rate_card", "write"

    it "removes the phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(contract_rate_card.rate_phases.order(:position).map(&:code)).to eq(%w[default])
    end
  end
end
