# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductItemFilterResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {filterId: product_item_filter.id}
    )
  end

  let(:required_permission) { "product_items:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_item_filter) { create(:product_item_filter, :with_values, organization:) }

  let(:query) do
    <<~GQL
      query($filterId: ID!) {
        productItemFilter(id: $filterId) {
          id name code
          values { key value }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:view"

  it "returns a single product item filter" do
    response = execution["data"]["productItemFilter"]

    expect(response["id"]).to eq(product_item_filter.id)
    expect(response["values"].count).to eq(1)
  end

  context "when the filter belongs to another organization" do
    let(:product_item_filter) { create(:product_item_filter) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
