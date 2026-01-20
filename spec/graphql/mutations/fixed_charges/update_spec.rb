# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::FixedCharges::Update, type: :graphql do
  let(:required_permission) { "charges:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:add_on) { create(:add_on, organization:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:) }

  let(:mutation) do
    <<~GQL
      mutation($input: FixedChargeUpdateInput!) {
        updateFixedCharge(input: $input) {
          id
          code
          invoiceDisplayName
          chargeModel
          units
          properties {
            amount
          }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "charges:update"

  it "updates a fixed charge" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: fixed_charge.id,
          chargeModel: "standard",
          invoiceDisplayName: "Updated Fixed Charge",
          units: "25",
          properties: {
            amount: "200"
          }
        }
      }
    )

    result_data = result["data"]["updateFixedCharge"]

    expect(result_data["id"]).to eq(fixed_charge.id)
    expect(result_data["invoiceDisplayName"]).to eq("Updated Fixed Charge")
    expect(result_data["units"]).to eq("25")
    expect(result_data["properties"]["amount"]).to eq("200")
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
            id: "unknown",
            invoiceDisplayName: "Updated"
          }
        }
      )

      expect_not_found(result)
    end
  end
end
