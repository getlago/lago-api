# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::PlanRateCards::RatePhasesController do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:) }
  let(:rate_card) { create(:rate_card, organization:) }
  let!(:plan_rate_card) { create(:plan_rate_card, organization:, plan:, rate_card:) }

  describe "GET /api/v2/plans/:plan_code/applied_rate_cards/:rate_card_code/rate_phases" do
    subject { get_with_token(organization, "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases") }

    let!(:rate_phase) { create(:rate_phase, organization:, plan_rate_card:, position: 1) }

    include_examples "requires API permission", "plan_rate_card", "read"

    it "returns the entry's rate phases with their codes" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phases].map { |phase| phase[:lago_id] }).to eq([rate_phase.id])
      expect(json[:rate_phases].map { |phase| phase[:code] }).to eq([rate_phase.code])
    end

    context "when the plan rate card does not exist" do
      subject { get_with_token(organization, "/api/v2/plans/#{plan.code}/applied_rate_cards/unknown/rate_phases") }

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("applied_rate_card")
      end
    end
  end

  describe "POST /api/v2/plans/:plan_code/applied_rate_cards/:rate_card_code/rate_phases" do
    subject do
      post_with_token(organization, "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases", {rate_phase: phase_params})
    end

    let!(:terminal) { create(:rate_phase, organization:, plan_rate_card:, position: 1, billing_interval_cycle_count: nil) }
    let(:phase_params) { {code: "launch", name: "Launch", billing_interval_cycle_count: 3} }

    include_examples "requires API permission", "plan_rate_card", "write"

    it "inserts the phase before the indefinite tail" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phase][:code]).to eq("launch")
      expect(json[:rate_phase][:position]).to eq(1)
      expect(terminal.reload.position).to eq(2)
    end

    context "with a rate override" do
      let(:phase_params) do
        {
          code: "trial",
          name: "trial",
          billing_interval_cycle_count: 3,
          rate_override: {rate_model: "standard", rate_properties: {amount: "0"}, min_amount_cents: 0}
        }
      end

      it "creates the override and returns it on the phase" do
        subject

        expect(response).to have_http_status(:success)
        override = json[:rate_phase][:rate_override]
        expect(override[:lago_id]).to be_present
        expect(override[:rate_model]).to eq("standard")
      end
    end

    context "when inserting an indefinite phase before the end" do
      let(:phase_params) { {position: 1, billing_interval_cycle_count: nil} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :billing_interval_cycle_count)).to eq(["indefinite_phase_must_be_last"])
      end
    end
  end

  describe "PUT /api/v2/plans/:plan_code/applied_rate_cards/:rate_card_code/rate_phases/:code" do
    subject do
      put_with_token(
        organization,
        "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/#{rate_phase.code}",
        {rate_phase: {name: "Renamed"}}
      )
    end

    let!(:rate_phase) { create(:rate_phase, organization:, plan_rate_card:, position: 1, code: "launch") }

    include_examples "requires API permission", "plan_rate_card", "write"

    it "updates the phase" do
      subject

      expect(response).to have_http_status(:success)
      expect(json[:rate_phase][:name]).to eq("Renamed")
    end

    context "when a position is provided" do
      subject do
        put_with_token(
          organization,
          "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/#{rate_phase.code}",
          {rate_phase: {name: "Renamed", position: 4}}
        )
      end

      it "does not permit it" do
        subject

        expect(response).to have_http_status(:success)
        expect(rate_phase.reload.position).to eq(1)
      end
    end

    context "when the override is an explicit null" do
      subject do
        put_with_token(
          organization,
          "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/#{rate_phase.code}",
          {rate_phase: {rate_override: nil}}
        )
      end

      let(:override) { create(:rate_override, organization:) }

      before { rate_phase.update!(rate_override_id: override.id) }

      it "clears the override" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:rate_phase][:rate_override]).to be_nil
        expect(rate_phase.reload.rate_override).to be_nil
        expect(override.reload).to be_discarded
      end
    end

    context "when the override is an empty object" do
      subject do
        put_with_token(
          organization,
          "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/#{rate_phase.code}",
          {rate_phase: {rate_override: {}}}
        )
      end

      let(:override) { create(:rate_override, organization:) }

      before { rate_phase.update!(rate_override_id: override.id) }

      it "fails validation instead of clearing the override" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(rate_phase.reload.rate_override).to eq(override)
      end
    end

    context "when the rate_phase wrapper is missing" do
      subject do
        put_with_token(
          organization,
          "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/#{rate_phase.code}",
          {}
        )
      end

      it "returns a bad request error" do
        subject

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when the override names a structural card field" do
      subject do
        put_with_token(
          organization,
          "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/#{rate_phase.code}",
          {rate_phase: {rate_override: {rate_model: "standard", rate_properties: {amount: "0.02"}, billing_timing: "advance"}}}
        )
      end

      it "rejects it instead of silently dropping the field" do
        subject

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json.dig(:error_details, :billing_timing)).to eq(["not_overridable"])
        expect(rate_phase.reload.rate_override).to be_nil
      end
    end

    context "when the phase does not exist" do
      subject do
        put_with_token(
          organization,
          "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/unknown",
          {rate_phase: {name: "Renamed"}}
        )
      end

      it "returns a not found error" do
        subject

        expect(response).to be_not_found_error("rate_phase")
      end
    end
  end

  describe "DELETE /api/v2/plans/:plan_code/applied_rate_cards/:rate_card_code/rate_phases/:code" do
    subject do
      delete_with_token(organization, "/api/v2/plans/#{plan.code}/applied_rate_cards/#{rate_card.code}/rate_phases/#{terminal.code}")
    end

    let!(:launch) { create(:rate_phase, organization:, plan_rate_card:, position: 1, billing_interval_cycle_count: 3) }
    let!(:terminal) { create(:rate_phase, organization:, plan_rate_card:, position: 2, billing_interval_cycle_count: nil) }

    include_examples "requires API permission", "plan_rate_card", "write"

    it "deletes the phase and promotes the new last phase to indefinite" do
      subject

      expect(response).to have_http_status(:success)
      expect(terminal.reload).to be_discarded
      expect(launch.reload.billing_interval_cycle_count).to be_nil
    end
  end
end
