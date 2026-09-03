# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::FixedCharges::Update, type: :graphql do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "charges:update" }
  let(:organization) { membership.organization }
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

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:plan) { create_default(:plan, organization:) }
  let_it_be(:add_on) { create_default(:add_on, organization:) }

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

  context "with cascade_updates" do
    let(:child_plan) { create(:plan, organization:, parent: plan) }
    let(:child_fixed_charge) { create(:fixed_charge, plan: child_plan, organization:, add_on:, parent: fixed_charge) }

    before do
      create(:subscription, plan: child_plan, status: :active)
      child_fixed_charge
    end

    it "passes cascade_updates to the service" do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: fixed_charge.id,
            chargeModel: "standard",
            cascadeUpdates: true,
            units: "25",
            properties: {
              amount: "200"
            }
          }
        }
      )

      expect(FixedCharges::UpdateChildrenJob).to have_been_enqueued
    end
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
