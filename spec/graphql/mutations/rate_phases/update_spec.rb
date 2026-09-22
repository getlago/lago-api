# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RatePhases::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let!(:rate_phase) { create(:rate_phase, organization:, plan_rate_card:, position: 1, code: "launch", name: "Before", billing_interval_cycle_count: 3) }

  let(:input) { {planAppliedRateCardId: plan_rate_card.id, code: rate_phase.code, name: "After", newCode: "intro"} }

  let(:mutation) do
    <<~GQL
      mutation($input: UpdateRatePhaseInput!) {
        updateRatePhase(input: $input) {
          id code name position
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "updates the phase addressed by its code" do
    response = execution["data"]["updateRatePhase"]

    expect(response["name"]).to eq("After")
    expect(response["code"]).to eq("intro")
  end

  context "when moving the phase" do
    let(:input) { {planAppliedRateCardId: plan_rate_card.id, code: rate_phase.code, position: 2} }

    before do
      create(:rate_phase, organization:, plan_rate_card:, position: 2, code: "ramp", billing_interval_cycle_count: 6)
      create(:rate_phase, organization:, plan_rate_card:, position: 3, code: "forever", billing_interval_cycle_count: nil)
    end

    it "reorders the sequence" do
      expect(execution["data"]["updateRatePhase"]["position"]).to eq(2)
      expect(plan_rate_card.rate_phases.order(:position).pluck(:code)).to eq(%w[ramp launch forever])
    end

    context "when taking the tail's slot" do
      let(:input) { {planAppliedRateCardId: plan_rate_card.id, code: rate_phase.code, position: 3} }

      it "returns a validation error" do
        expect_graphql_error(result: execution, message: "Unprocessable Entity")
      end
    end
  end

  context "when the phase does not exist" do
    let(:input) { {planAppliedRateCardId: plan_rate_card.id, code: "unknown", name: "After"} }

    it "returns an error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
