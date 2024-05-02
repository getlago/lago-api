# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationMappingsResolver, type: :graphql do
  let(:required_permission) { 'organization:integrations:view' }
  let(:query) do
    <<~GQL
      query {
        integrationMappings(limit: 5) {
          collection { id }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:netsuite_mapping) { create(:netsuite_mapping, integration:) }

  before { netsuite_mapping }

  it_behaves_like 'requires current user'
  it_behaves_like 'requires current organization'
  it_behaves_like 'requires permission', 'organization:integrations:view'

  it 'returns a list of mappings' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query:,
    )

    integration_mappings_response = result['data']['integrationMappings']

    aggregate_failures do
      expect(integration_mappings_response['collection'].count).to eq(1)
      expect(integration_mappings_response['collection'].first['id']).to eq(netsuite_mapping.id)

      expect(integration_mappings_response['metadata']['currentPage']).to eq(1)
      expect(integration_mappings_response['metadata']['totalCount']).to eq(1)
    end
  end
end
