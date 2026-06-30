# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductItemFilters::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "product_items:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product_item) { create(:product_item, organization:, billable_metric:) }
  let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }
  let(:scheme_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "scheme", values: %w[visa]) }

  let(:input) do
    {
      productItemId: product_item.id,
      name: "US Visa",
      code: "us_visa",
      values: [
        {billableMetricFilterId: region_filter.id, value: "us"},
        {billableMetricFilterId: scheme_filter.id, value: "visa"}
      ]
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateProductItemFilterInput!) {
        createProductItemFilter(input: $input) {
          id name code
          productItem { id }
          values { key value billableMetricFilter { id } }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:create"

  it "creates a product item filter with its values" do
    result_data = execution["data"]["createProductItemFilter"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("US Visa")
    expect(result_data["productItem"]["id"]).to eq(product_item.id)
    expect(result_data["values"].map { [it["key"], it["value"]] }).to match_array([%w[region us], %w[scheme visa]])
  end

  context "when values are empty" do
    before { input[:values] = [] }

    it "returns a validation error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end
end
