# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Charges::Update, type: :graphql do
  let(:required_permission) { "charges:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:plan) { create(:plan, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:) }

  let(:mutation) do
    <<~GQL
      mutation($input: ChargeUpdateInput!) {
        updateCharge(input: $input) {
          id
          code
          invoiceDisplayName
          chargeModel
          payInAdvance
          prorated
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

  it "updates a charge" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: charge.id,
          chargeModel: "standard",
          invoiceDisplayName: "Updated Charge",
          properties: {
            amount: "25"
          }
        }
      }
    )

    result_data = result["data"]["updateCharge"]

    expect(result_data["id"]).to eq(charge.id)
    expect(result_data["invoiceDisplayName"]).to eq("Updated Charge")
    expect(result_data["properties"]["amount"]).to eq("25")
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
            id: "unknown",
            invoiceDisplayName: "Updated"
          }
        }
      )

      expect_not_found(result)
    end
  end
end
