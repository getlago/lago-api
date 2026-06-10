# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::ProductItems::Create do
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
  let(:product) { create(:product, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:input) do
    {
      name: "Storage",
      code: "storage",
      itemType: "usage",
      productId: product.id,
      billableMetricId: billable_metric.id
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateProductItemInput!) {
        createProductItem(input: $input) {
          id name code itemType
          product { id }
          billableMetric { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "product_items:create"

  it "creates a product item" do
    result_data = execution["data"]["createProductItem"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("Storage")
    expect(result_data["code"]).to eq("storage")
    expect(result_data["itemType"]).to eq("usage")
    expect(result_data["product"]["id"]).to eq(product.id)
    expect(result_data["billableMetric"]["id"]).to eq(billable_metric.id)
  end

  context "with a standalone fixed item" do
    let(:input) { {name: "Seats", code: "seats", itemType: "fixed"} }

    it "creates the item without product nor metric" do
      result_data = execution["data"]["createProductItem"]

      expect(result_data["itemType"]).to eq("fixed")
      expect(result_data["product"]).to be_nil
      expect(result_data["billableMetric"]).to be_nil
    end
  end
end
