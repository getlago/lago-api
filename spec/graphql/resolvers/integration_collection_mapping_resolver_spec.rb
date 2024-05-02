# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationCollectionMappingResolver, type: :graphql do
  let(:required_permission) { 'organization:integrations:view' }
  let(:query) do
    <<~GQL
      query($collectionMappingId: ID!) {
        integrationCollectionMapping(id: $collectionMappingId) {
          id
          mappingType
          externalId
          externalAccountCode
          externalName
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:netsuite_collection_mapping) { create(:netsuite_collection_mapping, integration:) }

  before do
    netsuite_collection_mapping
  end

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:view'

  it 'returns a single integration collection mapping' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: { collectionMappingId: netsuite_collection_mapping.id },
    )

    integration_mapping_response = result['data']['integrationCollectionMapping']

    aggregate_failures do
      expect(integration_mapping_response['id']).to eq(netsuite_collection_mapping.id)
      expect(integration_mapping_response['mappingType']).to eq(netsuite_collection_mapping.mapping_type)
      expect(integration_mapping_response['externalId']).to eq(netsuite_collection_mapping.external_id)
      expect(integration_mapping_response['externalName']).to eq(netsuite_collection_mapping.external_name)
      expect(integration_mapping_response['externalAccountCode'])
        .to eq(netsuite_collection_mapping.external_account_code)
    end
  end

  context 'when integration mapping is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: { collectionMappingId: '123456' },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end
end
