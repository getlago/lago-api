# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::FixedCharges::Destroy, type: :graphql do
  let(:required_permission) { "fixed_charges:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }

  let(:mutation) do
    <<~GQL
      mutation($input: DestroyFixedChargeInput!) {
        destroyFixedCharge(input: $input) {
          id
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "fixed_charges:delete"

  it "destroys a fixed charge" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: fixed_charge.id
        }
      }
    )

    result_data = result["data"]["destroyFixedCharge"]

    expect(result_data["id"]).to eq(fixed_charge.id)
    expect(fixed_charge.reload.deleted_at).to be_present
  end

  context "when fixed charge does not exist" do
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
