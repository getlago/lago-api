# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductFilters::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "product_filters:create" }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:region_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[us eu]) }
  let(:scheme_filter) { create(:billable_metric_filter, organization:, billable_metric:, key: "scheme", values: %w[visa]) }
  let(:input) do
    {
      productId: product.id,
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
      mutation($input: CreateProductFilterInput!) {
        createProductFilter(input: $input) {
          id name code
          product { id }
          values { key value billableMetricFilter { id } }
        }
      }
    GQL
  end

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:membership) { create_default(:membership) }
  let_it_be(:billable_metric) { create_default(:billable_metric, organization:) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_filters:create"

  it "creates a product filter with its values" do
    result_data = execution["data"]["createProductFilter"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("US Visa")
    expect(result_data["product"]["id"]).to eq(product.id)
    expect(result_data["values"].map { [it["key"], it["value"]] }).to match_array([%w[region us], %w[scheme visa]])
  end

  context "when values are empty" do
    before { input[:values] = [] }

    it "returns a validation error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end

  context "with a key-only value selection" do
    before { input[:values] = [{billableMetricFilterId: region_filter.id}] }

    it "creates the filter matching any value of the key" do
      result_data = execution["data"]["createProductFilter"]

      expect(result_data["values"].map { [it["key"], it["value"]] }).to eq([["region", nil]])
    end
  end

  context "when a key-only entry is combined with a specific value for the same key" do
    before { input[:values] = [{billableMetricFilterId: region_filter.id}, {billableMetricFilterId: region_filter.id, value: "eu"}] }

    it "returns a validation error" do
      expect_graphql_error(result: execution, message: :unprocessable_entity)
    end
  end
end
