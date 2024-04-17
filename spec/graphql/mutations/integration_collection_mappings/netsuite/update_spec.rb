# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mutations::IntegrationCollectionMappings::Netsuite::Update, type: :graphql do
  let(:integration_collection_mapping) { create(:netsuite_collection_mapping, integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:mapping_type) { %i[fallback_item coupon subscription_fee minimum_commitment tax prepaid_credit].sample.to_s }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:netsuite_account_code) { Faker::Barcode.ean }
  let(:netsuite_id) { SecureRandom.uuid }
  let(:netsuite_name) { Faker::Commerce.department }

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateNetsuiteIntegrationCollectionMappingInput!) {
        updateNetsuiteIntegrationCollectionMapping(input: $input) {
          id,
          integrationId,
          mappingType,
          netsuiteAccountCode,
          netsuiteId,
          netsuiteName
        }
      }
    GQL
  end

  it 'updates a netsuite integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      query: mutation,
      variables: {
        input: {
          id: integration_collection_mapping.id,
          integrationId: integration.id,
          mappingType: mapping_type,
          netsuiteAccountCode: netsuite_account_code,
          netsuiteId: netsuite_id,
          netsuiteName: netsuite_name,
        },
      },
    )

    result_data = result['data']['updateNetsuiteIntegrationCollectionMapping']

    aggregate_failures do
      expect(result_data['integrationId']).to eq(integration.id)
      expect(result_data['mappingType']).to eq(mapping_type)
      expect(result_data['netsuiteAccountCode']).to eq(netsuite_account_code)
      expect(result_data['netsuiteId']).to eq(netsuite_id)
      expect(result_data['netsuiteName']).to eq(netsuite_name)
    end
  end

  context 'without current user' do
    it 'returns an error' do
      result = execute_graphql(
        current_organization: membership.organization,
        query: mutation,
        variables: {
          input: {
            id: integration_collection_mapping.id,
            integrationId: integration_collection_mapping.id,
            mappingType: mapping_type,
            netsuiteAccountCode: netsuite_account_code,
            netsuiteId: netsuite_id,
            netsuiteName: netsuite_name,
          },
        },
      )

      expect_unauthorized_error(result)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query: mutation,
        variables: {
          input: {
            id: integration_collection_mapping.id,
            integrationId: integration_collection_mapping.id,
            mappingType: mapping_type,
            netsuiteAccountCode: netsuite_account_code,
            netsuiteId: netsuite_id,
            netsuiteName: netsuite_name,
          },
        },
      )

      expect_forbidden_error(result)
    end
  end
end
