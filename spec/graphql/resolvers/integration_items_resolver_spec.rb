# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Resolvers::IntegrationItemsResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query($integrationId: ID!, $itemType: IntegrationItemTypeEnum) {
        integrationItems(integrationId: $integrationId, itemType: $itemType, limit: 5) {
          collection { id externalId itemType name }
          metadata { currentPage, totalCount }
        }
      }
    GQL
  end

  let(:integration_item) { create(:integration_item, integration:) }
  let(:integration_item2) { create(:integration_item, item_type: 'tax', integration:) }
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }

  before do
    integration_item
    integration_item2
  end

  it 'returns a list of integration items' do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {
        integrationId: integration.id,
        itemType: 'tax',
      },
    )

    integration_items_response = result['data']['integrationItems']

    aggregate_failures do
      expect(integration_items_response['collection'].count).to eq(1)
      expect(integration_items_response['collection'].first['id']).to eq(integration_item2.id)

      expect(integration_items_response['metadata']['currentPage']).to eq(1)
      expect(integration_items_response['metadata']['totalCount']).to eq(1)
    end
  end

  context 'without integration id' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
      )

      expect_graphql_error(
        result:,
        message: 'Variable $integrationId of type ID! was provided invalid value',
      )
    end
  end

  context 'without current organization' do
    it 'returns an error' do
      result = execute_graphql(
        current_user: membership.user,
        query:,
        variables: {
          integrationId: integration.id,
          itemType: 'tax',
        },
      )

      expect_graphql_error(
        result:,
        message: 'Missing organization id',
      )
    end
  end
end
