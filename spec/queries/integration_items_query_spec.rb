# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationItemsQuery, type: :query do
  subject(:integration_items_query) { described_class.new(organization:) }

  let(:query_filters) { {} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_second) { create(:netsuite_integration, organization:) }
  let(:integration_third) { create(:netsuite_integration) }

  let(:integration_item_first) { create(:integration_item, item_type: 'tax', integration:) }
  let(:integration_item_second) { create(:integration_item, integration: integration_second) }
  let(:integration_item_third) { create(:integration_item, integration: integration_third) }
  let(:integration_item_fourth) { create(:integration_item, name: 'Findme', integration:) }

  let(:service_call) do
    integration_items_query.call(integration_id: integration.id, search_term:, page: 1, limit: 10, filters:)
  end

  let(:search_term) { nil }

  before do
    integration_item_first
    integration_item_second
    integration_item_third
    integration_item_fourth
  end

  context 'when filters are empty' do
    let(:filters) { {} }

    it 'returns all integration items of an integration' do
      result = service_call

      returned_ids = result.integration_items.pluck(:id)

      aggregate_failures do
        expect(result.integration_items.count).to eq(2)
        expect(returned_ids).to include(integration_item_first.id)
        expect(returned_ids).not_to include(integration_item_second.id)
        expect(returned_ids).not_to include(integration_item_third.id)
        expect(returned_ids).to include(integration_item_fourth.id)
      end
    end
  end

  context 'when filtering by item type' do
    let(:filters) { { item_type: 'tax' } }

    it 'returns one integration item' do
      result = service_call

      returned_ids = result.integration_items.pluck(:id)

      aggregate_failures do
        expect(result.integration_items.count).to eq(1)
        expect(returned_ids).to include(integration_item_first.id)
        expect(returned_ids).not_to include(integration_item_second.id)
        expect(returned_ids).not_to include(integration_item_third.id)
        expect(returned_ids).not_to include(integration_item_fourth.id)
      end
    end
  end

  context 'when searching by name' do
    let(:search_term) { 'Findme' }
    let(:filters) { {} }

    it 'returns one integration item' do
      result = service_call

      returned_ids = result.integration_items.pluck(:id)

      aggregate_failures do
        expect(result.integration_items.count).to eq(1)
        expect(returned_ids).not_to include(integration_item_first.id)
        expect(returned_ids).not_to include(integration_item_second.id)
        expect(returned_ids).not_to include(integration_item_third.id)
        expect(returned_ids).to include(integration_item_fourth.id)
      end
    end
  end
end
