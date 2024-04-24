# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationCollectionMappings::NetsuiteCollectionMappingResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($netsuiteCollectionMappingId: ID!) {
        netsuiteCollectionMapping(id: $netsuiteCollectionMappingId) {
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

  it 'returns a single integration collection mapping' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { netsuiteCollectionMappingId: netsuite_collection_mapping.id },
    )

    integration_mapping_response = result['data']['netsuiteCollectionMapping']

    aggregate_failures do
      expect(integration_mapping_response['id']).to eq(netsuite_collection_mapping.id)
      expect(integration_mapping_response['mappingType']).to eq(netsuite_collection_mapping.mapping_type)
      expect(integration_mapping_response['externalId']).to eq(netsuite_collection_mapping.external_id)
      expect(integration_mapping_response['externalName']).to eq(netsuite_collection_mapping.external_name)
      expect(integration_mapping_response['externalAccountCode'])
        .to eq(netsuite_collection_mapping.external_account_code)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: { netsuiteCollectionMappingId: netsuite_collection_mapping.id },
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end

  context 'when integration mapping is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: { netsuiteCollectionMappingId: '123456' },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end
end
