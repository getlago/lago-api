# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntegrationMappingsQuery, type: :query do
  subject(:integration_mappings_query) { described_class.new(organization:, pagination:, filters:) }

  let(:pagination) { nil }
  let(:filters) { BaseQuery::Filters.new(query_filters) }
  let(:query_filters) { {} }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  let(:integration) { create(:netsuite_integration, organization:) }
  let(:integration_second) { create(:netsuite_integration, organization:) }
  let(:integration_third) { create(:netsuite_integration) }

  let(:integration_mapping_first) { create(:netsuite_mapping, integration:) }
  let(:integration_mapping_second) { create(:netsuite_mapping, integration:, mappable:) }
  let(:integration_mapping_third) { create(:netsuite_mapping, integration: integration_second) }
  let(:integration_mapping_fourth) { create(:netsuite_mapping, integration: integration_third) }

  let(:mappable) { create(:billable_metric, organization:) }

  before do
    integration_mapping_first
    integration_mapping_second
    integration_mapping_third
    integration_mapping_fourth
  end

  context 'when filters are empty' do
    it 'returns all mappings' do
      result = integration_mappings_query.call

      returned_ids = result.integration_mappings.pluck(:id)

      aggregate_failures do
        expect(result.integration_mappings.count).to eq(3)
        expect(returned_ids).to include(integration_mapping_first.id)
        expect(returned_ids).to include(integration_mapping_second.id)
        expect(returned_ids).to include(integration_mapping_third.id)
        expect(returned_ids).not_to include(integration_mapping_fourth.id)
      end
    end
  end

  context 'when filtering by integration id' do
    let(:query_filters) { {integration_id: integration.id} }

    it 'returns two mappings' do
      result = integration_mappings_query.call

      returned_ids = result.integration_mappings.pluck(:id)

      aggregate_failures do
        expect(result.integration_mappings.count).to eq(2)
        expect(returned_ids).to include(integration_mapping_first.id)
        expect(returned_ids).to include(integration_mapping_second.id)
        expect(returned_ids).not_to include(integration_mapping_third.id)
        expect(returned_ids).not_to include(integration_mapping_fourth.id)
      end
    end
  end

  context 'when filtering by mappable type' do
    let(:query_filters) { {mappable_type: 'BillableMetric'} }

    it 'returns one mapping' do
      result = integration_mappings_query.call

      returned_ids = result.integration_mappings.pluck(:id)

      aggregate_failures do
        expect(result.integration_mappings.count).to eq(1)
        expect(returned_ids).not_to include(integration_mapping_first.id)
        expect(returned_ids).to include(integration_mapping_second.id)
        expect(returned_ids).not_to include(integration_mapping_third.id)
        expect(returned_ids).not_to include(integration_mapping_fourth.id)
      end
    end
  end
end
