# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationCollectionMappingsResolver, type: :graphql do
  let(:required_permission) { 'organization:integrations:view' }
  let(:query) do
    <<~GQL
      query {
        integrationCollectionMappings(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:netsuite_collection_mapping) { create(:netsuite_collection_mapping, integration:) }

  before { netsuite_collection_mapping }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:view'

  it 'returns a list of mappings' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:
    )

    integration_collection_mappings_response = result['data']['integrationCollectionMappings']

    aggregate_failures do
      expect(integration_collection_mappings_response['collection'].count).to eq(1)
      expect(integration_collection_mappings_response['collection'].first['id']).to eq(netsuite_collection_mapping.id)

      expect(integration_collection_mappings_response['metadata']['currentPage']).to eq(1)
      expect(integration_collection_mappings_response['metadata']['totalCount']).to eq(1)
    end
  end
end
