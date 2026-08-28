# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Charges::Update, type: :graphql do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "charges:update" }
  let(:organization) { membership.organization }
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

  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:plan) { create_default(:plan, organization:) }
  let_it_be(:billable_metric) { create_default(:billable_metric, organization:) }

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

  context "with cascade_updates" do
    let(:child_plan) { create(:plan, organization:, parent: plan) }
    let(:child_charge) { create(:standard_charge, plan: child_plan, organization:, billable_metric:, parent: charge) }

    before do
      create(:subscription, plan: child_plan, status: :active)
      child_charge
    end

    it "passes cascade_updates to the service" do
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: charge.id,
            chargeModel: "standard",
            cascadeUpdates: true,
            properties: {
              amount: "25"
            }
          }
        }
      )

      expect(Charges::UpdateChildrenJob).to have_been_enqueued
    end
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
