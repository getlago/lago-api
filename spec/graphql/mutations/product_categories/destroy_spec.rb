# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductCategories::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: product_category.id}}
    )
  end

  let(:required_permission) { "product_categories:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_category) { create(:product_category, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyProductCategoryInput!) {
        destroyProductCategory(input: $input) { id }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_categories:delete"

  it "soft deletes the product_category" do
    expect(execution["data"]["destroyProductCategory"]["id"]).to eq(product_category.id)
    expect(product_category.reload).to be_discarded
  end

  context "when the product_category belongs to another organization" do
    let(:product_category) { create(:product_category) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
