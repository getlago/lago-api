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

  let(:default_position) { 1 }

  before do
    create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "default", position: default_position)
  end

  describe "GET .../rate_phases" do
    subject { get_with_token(organization, base_path) }

    include_examples "requires API permission", "contract_rate_card", "read"

    it "lists the phases" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { it[:code] }).to eq(%w[default])
    end

    context "with pagination parameters" do
      subject { get_with_token(organization, base_path, {page: 2, limit: 1}) }

      it "returns a bad request error for each parameter" do
        subject

        expect(response).to have_http_status(:bad_request)
        expect(json[:details]).to eq([{code: "not_paginated", field: "page", meta: {}}, {code: "not_paginated", field: "limit", meta: {}}])
      end
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
        expect(json[:details]).to eq([{code: "contract_locked", field: "rate_phase", meta: {}}])
      end
    end

    context "when a terminated contract reuses the external id" do
      subject do
        post_with_token(organization, "#{base_path}?contract_code=#{contract.code}", {rate_phase: {code: "ramp", position: 1, billing_interval_cycle_count: 2}})
      end

      before do
        create(:contract, :terminated, organization:, customer:, external_id: contract.external_id, started_at: 2.months.ago)
      end

      it "targets the contract identified by its code" do
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

    context "when moving a phase" do
      subject { put_with_token(organization, "#{base_path}/intro", {rate_phase: {position: 2}}) }

      let(:default_position) { 3 }

      before do
        create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "intro", position: 1, billing_interval_cycle_count: 1)
        create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "ramp", position: 2, billing_interval_cycle_count: 2)
      end

      it "reorders the card's phases" do
        subject

        expect(response).to have_http_status(:success)
        expect(contract_rate_card.rate_phases.order(:position).map(&:code)).to eq(%w[ramp intro default])
      end
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, organization:, customer:) }

      it "returns a contract_locked error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:details]).to eq([{code: "contract_locked", field: "rate_phase", meta: {}}])
      end
    end

    context "when the contract is a draft whose start has passed" do
      subject do
        put_with_token(organization, "#{base_path}/default", {rate_phase: {rate_override: {rate_model: "standard", rate_properties: {amount: "8"}}}})
      end

      let(:contract) { create(:contract, :draft, organization:, customer:, started_at: 1.month.ago) }
      let(:other_contract) { create(:contract, organization:, customer:) }
      let(:other_contract_rate_card) { create(:contract_rate_card, organization:, contract: other_contract, rate_card:) }

      before { create(:rate_phase, :contract_level, organization:, contract_rate_card: other_contract_rate_card, code: "default", position: 1) }

      it "saves the override on this contract only" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_phase][:rate_override]).to include(rate_model: "standard", rate_properties: {amount: "8"})
        expect(other_contract_rate_card.rate_phases.sole.rate_override).to be_nil
        expect(contract.reload).to be_draft
      end
    end
  end

  describe "DELETE .../rate_phases/:code" do
    subject { delete_with_token(organization, "#{base_path}/#{phase_code}") }

    let(:phase_code) { "extra" }
    let(:default_position) { 2 }

    let(:extra_override) { nil }
    let(:extra) do
      create(:rate_phase, :contract_level, organization:, contract_rate_card:, code: "extra", position: 1, billing_interval_cycle_count: 2, rate_override: extra_override)
    end

    before { extra }

    include_examples "requires API permission", "contract_rate_card", "write"

    it "removes the phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(contract_rate_card.rate_phases.order(:position).map(&:code)).to eq(%w[default])
      expect(json[:rate_phase][:deleted_at]).to eq(extra.reload.deleted_at.iso8601(6))
    end

    context "with a rate override" do
      let(:extra_override) { create(:rate_override, organization:) }

      it "returns the override with its deletion date" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_phase][:rate_override][:deleted_at]).to eq(extra_override.reload.deleted_at.iso8601(6))
      end
    end

    context "when deleting the indefinite tail" do
      let(:phase_code) { "default" }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json[:details]).to eq([{code: "indefinite_phase_not_deletable", field: "rate_phase", meta: {}}])
        expect(contract_rate_card.rate_phases.order(:position).map(&:code)).to eq(%w[extra default])
      end
    end
  end
end
