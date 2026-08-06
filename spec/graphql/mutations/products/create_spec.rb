# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Products::Create do
  subject(:execution) do
    execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input:}
    )
  end

  let(:required_permission) { "products:create" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:product_category) { create(:product_category, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:) }

  let(:input) do
    {
      name: "Storage",
      code: "storage",
      productType: "usage",
      productCategoryId: product_category.id,
      billableMetricId: billable_metric.id
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CreateProductInput!) {
        createProduct(input: $input) {
          id name code productType
          productCategory { id }
          billableMetric { id }
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:create"

  it "creates a product" do
    result_data = execution["data"]["createProduct"]

    expect(result_data["id"]).to be_present
    expect(result_data["name"]).to eq("Storage")
    expect(result_data["code"]).to eq("storage")
    expect(result_data["productType"]).to eq("usage")
    expect(result_data["productCategory"]["id"]).to eq(product_category.id)
    expect(result_data["billableMetric"]["id"]).to eq(billable_metric.id)
  end

  context "with a standalone fixed item" do
    let(:input) { {name: "Seats", code: "seats", productType: "fixed"} }

    it "creates the item without product_category nor metric" do
      result_data = execution["data"]["createProduct"]

      expect(result_data["productType"]).to eq("fixed")
      expect(result_data["productCategory"]).to be_nil
      expect(result_data["billableMetric"]).to be_nil
    end
  end

  context "when a usage item has no billable metric" do
    let(:input) { {name: "Orphan", code: "orphan", productType: "usage"} }

    it "returns a validation error on the relation" do
      expect(execution["errors"].first["extensions"]["details"]).to eq("billableMetric" => ["value_is_mandatory"])
    end
  end
end
