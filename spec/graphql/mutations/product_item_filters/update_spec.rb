# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductItemFilters::Update do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "product_items:update" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:billable_metric) { create(:billable_metric, organization:) }
  let(:product_item) { create(:product_item, organization:, billable_metric:) }
  let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }

  let(:product_item_filter) do
    filter = create(:product_item_filter, organization:, product_item:, name: "Before")
    create(:product_item_filter_value, organization:, product_item_filter: filter, billable_metric_filter: region_filter, value: "us")
    filter
  end

  let(:input) do
    {
      id: product_item_filter.id,
      name: "After",
      values: [{billableMetricFilterId: region_filter.id, value: "eu"}]
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateProductItemFilterInput!) {
        updateProductItemFilter(input: $input) {
          id name
          values { key value }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:update"

  it "updates the filter and replaces its values" do
    result_data = execution["data"]["updateProductItemFilter"]

    expect(result_data["name"]).to eq("After")
    expect(result_data["values"].map { [it["key"], it["value"]] }).to eq([%w[region eu]])
  end

  context "when the filter belongs to another organization" do
    let(:input) { {id: create(:product_item_filter).id, name: "After"} }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end
end
