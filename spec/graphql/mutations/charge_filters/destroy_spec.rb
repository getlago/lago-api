# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ChargeFilters::Destroy, type: :graphql do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "charges:delete" }
  let(:organization) { membership.organization }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }
  let(:charge_filter) { create(:charge_filter, charge:) }
  let(:mutation) do
    <<~GQL
      mutation($input: DestroyChargeFilterInput!) {
        destroyChargeFilter(input: $input) {
          id
        }
      }
    GQL
  end

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:plan) { create_default(:plan, organization:) }
  let_it_be(:billable_metric) { create_default(:billable_metric, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "charges:delete"

  it "destroys a charge filter" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: charge_filter.id
        }
      }
    )

    result_data = result["data"]["destroyChargeFilter"]

    expect(result_data["id"]).to eq(charge_filter.id)
    expect(charge_filter.reload.deleted_at).to be_present
  end

  context "with cascade_updates" do
    it "destroys a charge filter with cascade" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: charge_filter.id,
            cascadeUpdates: true
          }
        }
      )

      result_data = result["data"]["destroyChargeFilter"]

      expect(result_data["id"]).to eq(charge_filter.id)
      expect(charge_filter.reload.deleted_at).to be_present
    end
  end

  context "when charge filter does not exist" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: "unknown"
          }
        }
      )

      expect_not_found(result)
    end
  end
end
