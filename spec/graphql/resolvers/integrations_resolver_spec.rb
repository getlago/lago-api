# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        integrations(limit: 5) {
          collection {
            ... on NetsuiteIntegration {
              id
              code
              __typename
            }
          }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:netsuite_integration) { create(:netsuite_integration, organization:) }

  before { netsuite_integration }

  context 'when type is present' do
    let(:query) do
      <<~GQL
        query {
          integrations(limit: 5, type: netsuite) {
            collection {
              ... on NetsuiteIntegration {
                id
                code
                __typename
              }
            }
            metadata { currentPage, totalCount }
          }
        }
      GQL
    end

    it 'returns a list of integrations' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        query:,
      )

      integrations_response = result['data']['integrations']

      aggregate_failures do
        expect(integrations_response['collection'].count).to eq(1)
        expect(integrations_response['collection'].first['id']).to eq(netsuite_integration.id)

        expect(integrations_response['metadata']['currentPage']).to eq(1)
        expect(integrations_response['metadata']['totalCount']).to eq(1)
      end
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(current_user: membership.user, query:)

      expect_graphql_error(result:, message: 'Missing organization id')
    end
  end

  context 'when not member of the organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: create(:organization),
        query:,
      )

      expect_graphql_error(result:, message: 'Not in organization')
    end
  end
end
