# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationMappings::NetsuiteMappingResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($netsuiteMappingId: ID!) {
        netsuiteMapping(id: $netsuiteMappingId) {
          id
          mappableId
          mappableType
          netsuiteId
          netsuiteAccountCode
          netsuiteName
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:netsuite_mapping) { create(:netsuite_mapping, integration:) }

  before do
    netsuite_mapping
  end

  it 'returns a single integration mapping' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { netsuiteMappingId: netsuite_mapping.id },
    )

    integration_mapping_response = result['data']['netsuiteMapping']

    aggregate_failures do
      expect(integration_mapping_response['id']).to eq(netsuite_mapping.id)
      expect(integration_mapping_response['mappableId']).to eq(netsuite_mapping.mappable_id)
      expect(integration_mapping_response['mappableType']).to eq(netsuite_mapping.mappable_type)
      expect(integration_mapping_response['netsuiteId']).to eq(netsuite_mapping.netsuite_id)
      expect(integration_mapping_response['netsuiteName']).to eq(netsuite_mapping.netsuite_name)
      expect(integration_mapping_response['netsuiteAccountCode'])
        .to eq(netsuite_mapping.netsuite_account_code)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: { netsuiteMappingId: netsuite_mapping.id },
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
        variables: { netsuiteMappingId: '123456' },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end
end
