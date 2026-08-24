# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::RatePhases::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {planAppliedRateCardId: plan_rate_card.id, code: terminal.code}}
    )
  end

  let(:required_permission) { "plans:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan_rate_card) { create(:plan_rate_card, organization:) }

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

  it "removes the phase and promotes the new last phase to indefinite" do
    execution

    expect(terminal.reload).to be_discarded
    expect(launch.reload.billing_interval_cycle_count).to be_nil
  end

  context "when the organization is not on the product catalog" do
    before { organization.update!(feature_flags: organization.feature_flags - ["product_catalog"]) }

    it "returns a feature unavailable error" do
      expect(execution["errors"].first.dig("extensions", "code")).to eq("feature_unavailable")
    end
  end
end
