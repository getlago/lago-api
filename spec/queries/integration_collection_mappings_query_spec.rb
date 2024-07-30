# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationCollectionMappingsQuery, type: :query do
  subject(:collection_mappings_query) { described_class.new(organization:, pagination:, filters:) }

  let(:pagination) { nil }
  let(:filters) { {} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_second) { create(:netsuite_integration, organization:) }
  let(:integration_third) { create(:netsuite_integration) }

  let(:netsuite_collection_mapping_first) do
    create(:netsuite_collection_mapping, integration:, mapping_type: :fallback_item)
  end

  let(:netsuite_collection_mapping_second) { create(:netsuite_collection_mapping, integration:, mapping_type: :coupon) }

  let(:netsuite_collection_mapping_third) do
    create(:netsuite_collection_mapping, integration: integration_second, mapping_type: :subscription_fee)
  end

  let(:netsuite_collection_mapping_fourth) do
    create(:netsuite_collection_mapping, integration: integration_third, mapping_type: :minimum_commitment)
  end

  before do
    netsuite_collection_mapping_first
    netsuite_collection_mapping_second
    netsuite_collection_mapping_third
    netsuite_collection_mapping_fourth
  end

  context 'when filters are empty' do
    it 'returns all mappings' do
      result = collection_mappings_query.call

      returned_ids = result.integration_collection_mappings.pluck(:id)

      aggregate_failures do
        expect(result.integration_collection_mappings.count).to eq(3)
        expect(returned_ids).to include(netsuite_collection_mapping_first.id)
        expect(returned_ids).to include(netsuite_collection_mapping_second.id)
        expect(returned_ids).to include(netsuite_collection_mapping_third.id)
        expect(returned_ids).not_to include(netsuite_collection_mapping_fourth.id)
      end
    end
  end

  context 'when filtering by integration id' do
    let(:filters) { {integration_id: integration.id} }

    it 'returns two mappings' do
      result = collection_mappings_query.call

      returned_ids = result.integration_collection_mappings.pluck(:id)

      aggregate_failures do
        expect(result.integration_collection_mappings.count).to eq(2)
        expect(returned_ids).to include(netsuite_collection_mapping_first.id)
        expect(returned_ids).to include(netsuite_collection_mapping_second.id)
        expect(returned_ids).not_to include(netsuite_collection_mapping_third.id)
        expect(returned_ids).not_to include(netsuite_collection_mapping_fourth.id)
      end
    end
  end

  context 'when filtering by mapping type' do
    let(:filters) { {mapping_type: 'fallback_item'} }

    it 'returns one netsuite mappings' do
      result = collection_mappings_query.call

      returned_ids = result.integration_collection_mappings.pluck(:id)

      aggregate_failures do
        expect(result.integration_collection_mappings.count).to eq(1)
        expect(returned_ids).to include(netsuite_collection_mapping_first.id)
        expect(returned_ids).not_to include(netsuite_collection_mapping_second.id)
        expect(returned_ids).not_to include(netsuite_collection_mapping_third.id)
        expect(returned_ids).not_to include(netsuite_collection_mapping_fourth.id)
      end
    end
  end
end
