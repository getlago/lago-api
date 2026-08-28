# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductCategoriesResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "product_categories:view" }
  let(:organization) { membership.organization }
  let(:variables) { {} }
  let(:query) do
    <<~GQL
      query($searchTerm: String) {
        productCategories(limit: 5, searchTerm: $searchTerm) {
          collection { id name code }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end
  let!(:product_category) { create(:product_category, organization:, name: "Cards", code: "cards") }

  let_it_be(:membership) { create_default(:membership) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_categories:view"

  it "returns a list of product_categories" do
    response = execution["data"]["productCategories"]

    expect(response["collection"].count).to eq(1)
    expect(response["collection"].first["id"]).to eq(product_category.id)
    expect(response["metadata"]["totalCount"]).to eq(1)
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "nothing-matches"} }

    it "filters the results" do
      expect(execution["data"]["productCategories"]["collection"]).to be_empty
    end
  end
end
