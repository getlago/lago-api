# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationMappingsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:returned_ids) { result.integration_mappings.pluck(:id) }
  let(:pagination) { nil }
  let(:filters) { {} }
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

  context "when filters are empty" do
    it "returns all mappings" do
      expect(result.integration_mappings.count).to eq(3)
      expect(returned_ids).to include(integration_mapping_first.id)
      expect(returned_ids).to include(integration_mapping_second.id)
      expect(returned_ids).to include(integration_mapping_third.id)
      expect(returned_ids).not_to include(integration_mapping_fourth.id)
    end
  end

  context "when mappings have the same values for the ordering criteria" do
    let(:integration_mapping_second) do
      create(:netsuite_mapping, integration:, mappable:, created_at: integration_mapping_first.created_at).tap do |integration_mapping|
        integration_mapping.update! id: "00000000-0000-0000-0000-000000000000"
      end
    end

    it "returns a consistent list" do
      expect(result).to be_success
      expect(returned_ids.count).to eq(3)
      expect(returned_ids).to include(integration_mapping_first.id)
      expect(returned_ids).to include(integration_mapping_second.id)
      expect(returned_ids.index(integration_mapping_first.id)).to be > returned_ids.index(integration_mapping_second.id)
    end
  end

  context "with pagination" do
    let(:pagination) { {page: 2, limit: 2} }

    it "applies the pagination" do
      expect(result).to be_success
      expect(result.integration_mappings.count).to eq(1)
      expect(result.integration_mappings.current_page).to eq(2)
      expect(result.integration_mappings.prev_page).to eq(1)
      expect(result.integration_mappings.next_page).to be_nil
      expect(result.integration_mappings.total_pages).to eq(2)
      expect(result.integration_mappings.total_count).to eq(3)
    end
  end

  context "when filtering by integration id" do
    let(:filters) { {integration_id: integration.id} }

    it "returns two mappings" do
      expect(result.integration_mappings.count).to eq(2)
      expect(returned_ids).to include(integration_mapping_first.id)
      expect(returned_ids).to include(integration_mapping_second.id)
      expect(returned_ids).not_to include(integration_mapping_third.id)
      expect(returned_ids).not_to include(integration_mapping_fourth.id)
    end
  end

  context "when filtering by mappable type" do
    let(:filters) { {mappable_type: "BillableMetric"} }

    it "returns one mapping" do
      expect(result.integration_mappings.count).to eq(1)
      expect(returned_ids).not_to include(integration_mapping_first.id)
      expect(returned_ids).to include(integration_mapping_second.id)
      expect(returned_ids).not_to include(integration_mapping_third.id)
      expect(returned_ids).not_to include(integration_mapping_fourth.id)
    end
  end
end
