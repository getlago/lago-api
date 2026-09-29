# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RatePhases::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {planAppliedRateCardId: plan_rate_card.id, code: phase_code}}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }
  let(:phase_code) { launch.code }

  let!(:launch) { create(:rate_phase, organization:, plan_rate_card:, position: 1, billing_interval_cycle_count: 3) }
  let!(:terminal) { create(:rate_phase, organization:, plan_rate_card:, position: 2, billing_interval_cycle_count: nil) }

  let(:mutation) do
    <<~GQL
      mutation($input: DestroyRatePhaseInput!) {
        destroyRatePhase(input: $input) {
          id code
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "plans:update"

  it "removes the phase and shifts the tail up" do
    execution

    expect(launch.reload).to be_discarded
    expect(terminal.reload.position).to eq(1)
  end

  context "when deleting the indefinite tail" do
    let(:phase_code) { terminal.code }

    it "returns a validation error and keeps the phase" do
      expect_graphql_error(result: execution, message: "Unprocessable Entity")
      expect(terminal.reload).not_to be_discarded
    end
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
