# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::OrderFormResolver do
  let(:required_permission) { "order_forms:view" }

  let(:query) do
    <<~GQL
      query($id: ID!) {
        orderForm(id: $id) {
          id
          number
          status
          createdAt
          updatedAt
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form) { create(:order_form, organization:, customer:, quote:) }

  before { order_form }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "order_forms:view"

  it "returns a single order form" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {id: order_form.id}
    )

    data = result["data"]["orderForm"]

    expect(data["id"]).to eq(order_form.id)
    expect(data["number"]).to eq(order_form.number)
    expect(data["status"]).to eq("generated")
  end

  context "when order form is not found" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {id: SecureRandom.uuid}
      )

      expect_graphql_error(result:, message: "Resource not found")
    end
  end
end
