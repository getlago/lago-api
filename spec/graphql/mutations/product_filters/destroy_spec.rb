# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductFilters::Destroy do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {id: product_filter.id}}
    )
  end

  let(:required_permission) { "product_filters:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_filter) { create(:product_filter, :with_values, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyProductFilterInput!) {
        destroyProductFilter(input: $input) { id }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_filters:delete"

  it "soft deletes the filter" do
    expect(execution["data"]["destroyProductFilter"]["id"]).to eq(product_filter.id)
    expect(product_filter.reload).to be_discarded
  end

  context "when the filter belongs to another organization" do
    let(:product_filter) { create(:product_filter) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
