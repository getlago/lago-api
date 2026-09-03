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
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let!(:rate_phase) { create(:rate_phase, organization:, plan_rate_card:, position: 1, code: "launch", name: "Before") }
  let(:input) { {planAppliedRateCardId: plan_rate_card.id, code: rate_phase.code, name: "After", newCode: "intro"} }
  let(:mutation) do
    <<~GQL
      mutation($input: UpdateRatePhaseInput!) {
        updateRatePhase(input: $input) {
          id code name
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:plan) { create_default(:plan) }
  let_it_be(:membership) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "updates the phase addressed by its code" do
    response = execution["data"]["updateRatePhase"]

    expect(response["name"]).to eq("After")
    expect(response["code"]).to eq("intro")
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
