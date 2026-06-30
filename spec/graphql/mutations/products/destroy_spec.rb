# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Products::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: product.id}}
    )
  end

  let(:required_permission) { "products:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product) { create(:product, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyProductInput!) {
        destroyProduct(input: $input) { id }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:delete"

  it "soft deletes the product" do
    expect(execution["data"]["destroyProduct"]["id"]).to eq(product.id)
    expect(product.reload).to be_discarded
  end

  context "when the product belongs to another organization" do
    let(:product) { create(:product) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
