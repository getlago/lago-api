# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::ProductResolver do
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
  let(:product) { create(:product, organization:) }
  let(:variables) { {productId: product.id} }

  let(:query) do
    <<~GQL
      query($productId: ID!) {
        product(id: $productId) {
          id name code productType
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "products:view"

  it "returns a single product" do
    response = execution["data"]["product"]

    expect(response["id"]).to eq(product.id)
    expect(response["name"]).to eq(product.name)
    expect(response["productType"]).to eq("usage")
  end

  context "when the product belongs to another organization" do
    let(:product) { create(:product) }

    it "returns a not found error" do
      expect_graphql_error(result: execution, message: "Resource not found")
    end
  end

  context "with integration mappings" do
    let(:netsuite_integration) { create(:netsuite_integration, organization:) }
    let(:xero_integration) { create(:xero_integration, organization:) }
    let!(:netsuite_mapping) { create(:netsuite_mapping, integration: netsuite_integration, organization:, mappable: product) }
    let!(:xero_mapping) { create(:xero_mapping, integration: xero_integration, organization:, mappable: product) }
    let(:integration_id) { nil }
    let(:variables) { {productId: product.id, integrationId: integration_id} }

    let(:query) do
      <<~GQL
        query($productId: ID!, $integrationId: ID) {
          product(id: $productId) {
            integrationMappings(integrationId: $integrationId) { id }
          }
        }
      GQL
    end

    it "returns all Product integration mappings" do
      mappings = execution.dig("data", "product", "integrationMappings")

      expect(mappings.pluck("id")).to match_array([netsuite_mapping.id, xero_mapping.id])
    end

    context "with an integration ID" do
      let(:integration_id) { netsuite_integration.id }

      it "returns only the mapping for that integration" do
        mappings = execution.dig("data", "product", "integrationMappings")

        expect(mappings.pluck("id")).to eq([netsuite_mapping.id])
      end
    end
  end
end
