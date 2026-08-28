# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RatePhases::Create do
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
  let!(:terminal) { create(:rate_phase, organization:, plan_rate_card:, position: 1, billing_interval_cycle_count: nil) }
  let(:input) do
    {planAppliedRateCardId: plan_rate_card.id, code: "launch", name: "Launch", billingIntervalCycleCount: 3}
  end
  let(:mutation) do
    <<~GQL
      mutation($input: CreateRatePhaseInput!) {
        createRatePhase(input: $input) {
          id code position name billingIntervalCycleCount
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

  it "inserts the phase before the indefinite tail" do
    response = execution["data"]["createRatePhase"]

    expect(response["code"]).to eq("launch")
    expect(response["position"]).to eq(1)
    expect(terminal.reload.position).to eq(2)
  end

  context "with a rate override" do
    let(:input) do
      {
        planAppliedRateCardId: plan_rate_card.id,
        code: "overridden",
        billingIntervalCycleCount: 3,
        rateOverride: {rateModel: "standard", rateProperties: {amount: "0"}}
      }
    end

    let(:mutation) do
      <<~GQL
        mutation($input: CreateRatePhaseInput!) {
          createRatePhase(input: $input) {
            id code rateOverride { id rateModel }
          }
        }
      GQL
    end

    it "creates the override on the phase" do
      response = execution["data"]["createRatePhase"]

      expect(response["rateOverride"]["rateModel"]).to eq("standard")
    end
  end

  context "when inserting an indefinite phase before the end" do
    let(:input) { {planAppliedRateCardId: plan_rate_card.id, code: "bad", position: 1, billingIntervalCycleCount: nil} }

    it "returns an error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
