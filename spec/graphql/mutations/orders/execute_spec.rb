# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Orders::Execute do
  let(:required_permission) { "orders:execute" }
  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:membership) { create(:membership, organization:) }
  let(:customer) { create(:customer, organization:) }
  let(:order) { create(:order, organization:, customer:, execution_mode: "order_only") }

  let(:mutation) do
    <<~GQL
      mutation($input: ExecuteOrderInput!) {
        executeOrder(input: $input) {
          id
          status
          executedAt
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "orders:execute"

  it "executes the order", :premium do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: order.id}}
    )

    data = result["data"]["executeOrder"]

    expect(data["id"]).to eq(order.id)
    expect(data["status"]).to eq("executed")
    expect(data["executedAt"]).to be_present
  end

  context "without a premium license" do
    it "returns a forbidden error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: order.id}}
      )

      expect_graphql_error(result:, message: "feature_unavailable")
    end
  end

  context "when order is not executable", :premium do
    let(:order) { create(:order, :executed_order_only, organization:, customer:) }

    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: order.id}}
      )

      expect_graphql_error(result:, message: "Unprocessable Entity", details: {status: ["not_executable"]})
    end
  end

  context "when order is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {id: SecureRandom.uuid}}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
