# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationMappings::NetsuiteMappingsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        netsuiteMappings(limit: 5) {
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

  it 'returns a list of netsuite mappings' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
    )

    netsuite_mappings_response = result['data']['netsuiteMappings']

    aggregate_failures do
      expect(netsuite_mappings_response['collection'].count).to eq(1)
      expect(netsuite_mappings_response['collection'].first['id']).to eq(netsuite_mapping.id)

      expect(netsuite_mappings_response['metadata']['currentPage']).to eq(1)
      expect(netsuite_mappings_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end
end
