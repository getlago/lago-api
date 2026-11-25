# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::IntegrationItemsResolver do
  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:user) { create_default(:user) }
  let(:required_permission) { "organization:integrations:view" }
  let(:query) do
    <<~GQL
      query($integrationId: ID!, $itemType: IntegrationItemTypeEnum) {
        integrationItems(integrationId: $integrationId, itemType: $itemType, limit: 5) {
          collection { id externalId itemType externalName }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:integration_item) { create(:integration_item, integration:) }
  let(:integration_item2) { create(:integration_item, item_type: "tax", integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }

  let_it_be(:membership) { create_default(:membership) }

  before do
    integration_item
    integration_item2
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:view"

  it "returns a list of integration items" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {
        integrationId: integration.id,
        itemType: "tax"
      }
    )

    integration_items_response = result["data"]["integrationItems"]

    expect(integration_items_response["collection"].count).to eq(1)
    expect(integration_items_response["collection"].first["id"]).to eq(integration_item2.id)

    expect(integration_items_response["metadata"]["currentPage"]).to eq(1)
    expect(integration_items_response["metadata"]["totalCount"]).to eq(1)
  end

  context "with customer items" do
    let(:customer_item) do
      create(:integration_item, integration:, item_type: "customer", external_account_code: nil, external_name: "Acme Corp")
    end
    let(:account_item) { create(:integration_item, integration:, item_type: "account") }

    before do
      customer_item
      account_item
    end

    it "returns only customer items when filtering by customer" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {integrationId: integration.id, itemType: "customer"}
      )

      collection = result["data"]["integrationItems"]["collection"]
      ids = collection.map { |item| item["id"] }

      expect(ids).to eq([customer_item.id])
      expect(collection.first["itemType"]).to eq("customer")
      expect(collection.first["externalName"]).to eq("Acme Corp")
      expect(ids).not_to include(integration_item.id, integration_item2.id, account_item.id)
      expect(result["data"]["integrationItems"]["metadata"]["totalCount"]).to eq(1)
    end

    %w[standard account].each do |item_type|
      it "does not return customer items when filtering by #{item_type}" do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: organization,
          permissions: required_permission,
          query:,
          variables: {integrationId: integration.id, itemType: item_type}
        )

        collection = result["data"]["integrationItems"]["collection"]

        expect(collection).not_to be_empty
        expect(collection.map { |item| item["itemType"] }).to all(eq(item_type))
        expect(collection.map { |item| item["id"] }).not_to include(customer_item.id)
      end
    end
  end

  context "without integration id" do
    it "returns an error" do
      result = execute_graphql(
        current_user: membership.user,
        permissions: required_permission,
        query:
      )

      expect_graphql_error(
        result:,
        message: "Variable $integrationId of type ID! was provided invalid value"
      )
    end
  end
end
