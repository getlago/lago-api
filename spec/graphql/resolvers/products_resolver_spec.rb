# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductsResolver do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables:
    )
  end

  let(:required_permission) { "products:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:variables) { {} }

  let(:query) do
    <<~GQL
      query($searchTerm: String) {
        products(limit: 5, searchTerm: $searchTerm) {
          collection { id name code }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let!(:product) { create(:product, organization:, name: "Cards", code: "cards") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:view"

  it "returns a list of products" do
    response = execution["data"]["products"]

    expect(response["collection"].count).to eq(1)
    expect(response["collection"].first["id"]).to eq(product.id)
    expect(response["metadata"]["totalCount"]).to eq(1)
  end

  context "with a search term" do
    let(:variables) { {searchTerm: "nothing-matches"} }

    it "filters the results" do
      expect(execution["data"]["products"]["collection"]).to be_empty
    end
  end
end
