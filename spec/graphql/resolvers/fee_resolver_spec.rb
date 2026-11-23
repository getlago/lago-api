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

  context "with an add_on fee" do
    let(:add_on) { create(:add_on, organization:) }
    let(:fee) do
      create(
        :one_off_fee,
        organization:,
        add_on:,
        properties: {
          "from_datetime" => "2026-08-05T00:00:00.000-07:00",
          "to_datetime" => "2026-08-05T23:59:59.999-07:00"
        }
      )
    end

    let(:query) do
      <<~GQL
        query($feeId: ID!) {
          fee(id: $feeId) {
            id
            properties {
              fromDatetime
              toDatetime
            }
          }
        }
      GQL
    end

    it "returns the fee's stored period, matching Query.invoice" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {feeId: fee.id}
      )

      expect(result["data"]["fee"]["properties"]).to eq(
        "fromDatetime" => "2026-08-05T00:00:00+00:00",
        "toDatetime" => "2026-08-05T00:00:00+00:00"
      )
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
