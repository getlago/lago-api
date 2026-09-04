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
      query($searchTerm: String, $productType: ProductTypeEnum, $productCategoryIds: [ID!], $withoutProductCategory: Boolean) {
        products(limit: 5, searchTerm: $searchTerm, productType: $productType, productCategoryIds: $productCategoryIds, withoutProductCategory: $withoutProductCategory) {
          collection { id name code productType }
          metadata { currentPage totalCount }
        }
      }
    GQL
  end

  let(:product_category) { create(:product_category, organization:) }
  let!(:usage_item) { create(:product, organization:, product_category:, name: "Storage", code: "storage") }
  let!(:fixed_item) { create(:product, :fixed, :standalone, organization:, name: "Seats", code: "seats") }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:view"

  it "returns the products of the organization" do
    response = execution["data"]["products"]

    expect(response["collection"].map { it["id"] }).to match_array([usage_item.id, fixed_item.id])
    expect(response["metadata"]["totalCount"]).to eq(2)
  end

  context "with integration mappings" do
    let(:integration) { create(:anrok_integration, organization:) }
    let(:other_integration) { create(:xero_integration, organization:) }
    let!(:usage_mapping) { create(:anrok_mapping, integration:, organization:, mappable: usage_item) }
    let!(:fixed_mapping) { create(:anrok_mapping, integration:, organization:, mappable: fixed_item) }
    let(:variables) { {integrationId: integration.id} }

    let(:query) do
      <<~GQL
        query($integrationId: ID) {
          products(limit: 5) {
            collection { id integrationMappings(integrationId: $integrationId) { id } }
          }
        }
      GQL
    end

    before do
      create(:xero_mapping, integration: other_integration, organization:, mappable: usage_item)
    end

    it "loads filtered mappings for all Products in one query" do
      query_count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        query_count += 1 if payload[:sql]&.include?('FROM "integration_mappings"')
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { execution }

      products = execution.dig("data", "products", "collection").index_by { it["id"] }
      expect(products[usage_item.id]["integrationMappings"].pluck("id")).to eq([usage_mapping.id])
      expect(products[fixed_item.id]["integrationMappings"].pluck("id")).to eq([fixed_mapping.id])
      expect(query_count).to eq(1)
    end
  end

  context "with an item type filter" do
    let(:variables) { {productType: "fixed"} }

    it "returns only matching items" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to eq([fixed_item.id])
    end
  end

  context "with a product_category filter" do
    let(:variables) { {productCategoryIds: [product_category.id]} }

    it "returns only the items of those product_categories" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to eq([usage_item.id])
    end
  end

  context "with a without product_category filter" do
    let(:variables) { {withoutProductCategory: true} }

    it "returns only the items not attached to any product_category" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to eq([fixed_item.id])
    end
  end

  context "with product_category and without product_category filters combined" do
    let(:variables) { {productCategoryIds: [product_category.id], withoutProductCategory: true} }

    it "returns the union of both" do
      expect(execution["data"]["products"]["collection"].map { it["id"] }).to match_array([usage_item.id, fixed_item.id])
    end
  end
end
