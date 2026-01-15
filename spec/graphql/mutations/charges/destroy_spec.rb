# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Charges::Destroy, type: :graphql do
  let(:required_permission) { "charges:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DestroyChargeInput!) {
        destroyCharge(input: $input) {
          id
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "charges:delete"

  it "destroys a charge" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: charge.id
        }
      }
    )

    result_data = result["data"]["destroyCharge"]

    expect(result_data["id"]).to eq(charge.id)
    expect(charge.reload.deleted_at).to be_present
  end

  context "when charge does not exist" do
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
