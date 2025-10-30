# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::IntegrationCollectionMappings::Update do
  let(:required_permission) { "organization:integrations:update" }
  let(:integration_collection_mapping) { create(:netsuite_collection_mapping, integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:mapping_type) { %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit].sample.to_s }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:external_account_code) { Faker::Barcode.ean }
  let(:external_id) { SecureRandom.uuid }
  let(:external_name) { Faker::Commerce.department }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateIntegrationCollectionMappingInput!) {
        updateIntegrationCollectionMapping(input: $input) {
          id,
          integrationId,
          mappingType,
          externalAccountCode,
          externalId,
          externalName
          currencies {currencyCode currencyExternalCode}
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:integrations:update"

  it "updates a netsuite integration" do
    original_integration_id = integration_collection_mapping.integration_id
    original_mapping_type = integration_collection_mapping.mapping_type
    different_integration = create(:netsuite_integration, organization:)
    different_mapping_type = %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit].reject { |type| type.to_s == original_mapping_type }.sample.to_s

    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: required_permission,
      query: mutation,
      variables: {
        input: {
          id: integration_collection_mapping.id,
          integrationId: different_integration.id,
          mappingType: different_mapping_type,
          externalAccountCode: external_account_code,
          externalId: external_id,
          externalName: external_name,
          currencies: [
            {currencyCode: "GBP", currencyExternalCode: "70000"},
            {currencyCode: "EUR", currencyExternalCode: "300"}
          ]
        }
      }
    )

    expect(integration_collection_mapping.reload.currencies).to eq({
      "GBP" => "70000", "EUR" => "300"
    })
    result_data = result["data"]["updateIntegrationCollectionMapping"]

    # Deprecated fields should be ignored - original values should remain
    expect(result_data["integrationId"]).to eq(original_integration_id)
    expect(result_data["mappingType"]).to eq(original_mapping_type)
    # Other fields should be updated normally
    expect(result_data["externalAccountCode"]).to eq(external_account_code)
    expect(result_data["externalId"]).to eq(external_id)
    expect(result_data["externalName"]).to eq(external_name)
    expect(result_data["currencies"]).to contain_exactly(
      {"currencyCode" => "GBP", "currencyExternalCode" => "70000"},
      {"currencyCode" => "EUR", "currencyExternalCode" => "300"}
    )
  end

  context "when currency_code is duplicated" do
    it "returns a graphql error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: integration_collection_mapping.id,
            currencies: [
              {currencyCode: "EUR", currencyExternalCode: "1"},
              {currencyCode: "EUR", currencyExternalCode: "2"},
              {currencyCode: "GBP", currencyExternalCode: "3"},
              {currencyCode: "USD", currencyExternalCode: "4"},
              {currencyCode: "USD", currencyExternalCode: "4"}
            ]
          }
        }
      )

      expect_graphql_error(result:, message: "duplicate_currency_code")
    end
  end

  context "when currencies is empty" do
    it "returns a graphql error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: integration_collection_mapping.id,
            currencies: []
          }
        }
      )

      expect_unprocessable_entity(result, details: {
        currencies: ["cannot_be_empty"]
      })
    end
  end

  context "when currencies mapping has an empty value" do
    it "returns a graphql error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {
          input: {
            id: integration_collection_mapping.id,
            currencies: [
              {currencyCode: "EUR", currencyExternalCode: "1"},
              {currencyCode: "USD", currencyExternalCode: ""}
            ]
          }
        }
      )

      expect_unprocessable_entity(result, details: {
        currencies: ["invalid_format"]
      })
    end
  end
end
