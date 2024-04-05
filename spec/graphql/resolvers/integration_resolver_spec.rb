# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($integrationId: ID!) {
        integration(id: $integrationId) {
          ... on NetsuiteIntegration {
            id
            code
            name
            __typename
          }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }
  let(:netsuite_integration) { create(:netsuite_integration, organization:) }

  before do
    customer
    netsuite_integration
  end

  it 'returns a single integration' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: { integrationId: netsuite_integration.id },
    )

    integration_response = result['data']['integration']

    aggregate_failures do
      expect(integration_response['id']).to eq(netsuite_integration.id)
      expect(integration_response['code']).to eq(netsuite_integration.code)
      expect(integration_response['name']).to eq(netsuite_integration.name)
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: { integrationId: netsuite_integration.id },
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end

  context 'when integration is not found' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
        variables: { integrationId: 'foo' },
      )

      expect_graphql_error(
        result:,
        message: 'Resource not found',
      )
    end
  end
end
