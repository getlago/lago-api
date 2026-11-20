# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::FeeResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }
  let(:required_permission) { "invoices:view" }
  let(:fee) { create(:charge_fee, organization:, units: 3, precise_unit_amount: 100) }

  let(:query) do
    <<~GQL
      query($feeId: ID!) {
        fee(id: $feeId) {
          id
          units
          preciseUnitAmount
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "invoices:view"

  it "returns the fee" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {feeId: fee.id}
    )

    fee_response = result["data"]["fee"]

    expect(fee_response["id"]).to eq(fee.id)
    expect(fee_response["units"]).to eq(3)
    expect(fee_response["preciseUnitAmount"]).to eq(100)
  end

  context "when the fee does not exist" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {feeId: "invalid"}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end

  context "when the fee belongs to another organization" do
    let(:other_organization) { create(:organization) }
    let(:fee) { create(:charge_fee, organization: other_organization) }

    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {feeId: fee.id}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
