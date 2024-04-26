# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationMappings::NetsuiteMappingsQuery, type: :query do
  subject(:netsuite_mappings_query) { described_class.new(organization:) }

  let(:filters) { {} }
  let(:search_term) { nil }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_id) { integration.id }
  let(:integration_second) { create(:netsuite_integration, organization:) }
  let(:integration_third) { create(:netsuite_integration) }

  let(:netsuite_mapping_first) { create(:netsuite_mapping, integration:) }
  let(:netsuite_mapping_second) { create(:netsuite_mapping, integration:, mappable:) }
  let(:netsuite_mapping_third) { create(:netsuite_mapping, integration: integration_second) }
  let(:netsuite_mapping_fourth) { create(:netsuite_mapping, integration: integration_third) }

  let(:mappable) { create(:billable_metric, organization:) }

  before do
    netsuite_mapping_first
    netsuite_mapping_second
    netsuite_mapping_third
    netsuite_mapping_fourth
  end

  context 'when filters are empty' do
    it 'returns all netsuite mappings' do
      result = netsuite_mappings_query.call(search_term:, integration_id: nil, page: 1, limit: 10, filters:)

      returned_ids = result.netsuite_mappings.pluck(:id)

      aggregate_failures do
        expect(result.netsuite_mappings.count).to eq(3)
        expect(returned_ids).to include(netsuite_mapping_first.id)
        expect(returned_ids).to include(netsuite_mapping_second.id)
        expect(returned_ids).to include(netsuite_mapping_third.id)
        expect(returned_ids).not_to include(netsuite_mapping_fourth.id)
      end
    end
  end

  context 'when filtering by integration id' do
    let(:filters) { { integration_id: integration.id } }

    it 'returns two netsuite mappings' do
      result = netsuite_mappings_query.call(search_term:, integration_id:, page: 1, limit: 10, filters:)

      returned_ids = result.netsuite_mappings.pluck(:id)

      aggregate_failures do
        expect(result.netsuite_mappings.count).to eq(2)
        expect(returned_ids).to include(netsuite_mapping_first.id)
        expect(returned_ids).to include(netsuite_mapping_second.id)
        expect(returned_ids).not_to include(netsuite_mapping_third.id)
        expect(returned_ids).not_to include(netsuite_mapping_fourth.id)
      end
    end
  end

  context 'when filtering by mappable type' do
    let(:filters) { { mappable_type: 'BillableMetric' } }

    it 'returns one netsuite mappings' do
      result = netsuite_mappings_query.call(search_term:, integration_id:, page: 1, limit: 10, filters:)

      returned_ids = result.netsuite_mappings.pluck(:id)

      aggregate_failures do
        expect(result.netsuite_mappings.count).to eq(1)
        expect(returned_ids).not_to include(netsuite_mapping_first.id)
        expect(returned_ids).to include(netsuite_mapping_second.id)
        expect(returned_ids).not_to include(netsuite_mapping_third.id)
        expect(returned_ids).not_to include(netsuite_mapping_fourth.id)
      end
    end
  end
end
