# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::IntegrationMappingsByMappable do
  subject(:source) { described_class.new(integration_id) }

  let(:organization) { create(:organization) }
  let(:integration) { create(:anrok_integration, organization:) }
  let(:other_integration) { create(:xero_integration, organization:) }
  let(:integration_id) { integration.id }
  let(:product) { create(:product, organization:) }
  let(:other_product) { create(:product, organization:) }
  let!(:mapping) { create(:anrok_mapping, integration:, organization:, mappable: product) }
  let!(:other_mapping) { create(:anrok_mapping, integration:, organization:, mappable: other_product) }
  let!(:mapping_for_other_integration) do
    create(:xero_mapping, integration: other_integration, organization:, mappable: product)
  end

  describe "#fetch" do
    it "returns mappings for the requested integration grouped by mappable" do
      expect(source.fetch([product, other_product])).to eq([[mapping], [other_mapping]])
    end

    context "without an integration ID" do
      let(:integration_id) { nil }

      it "returns all mappings grouped by mappable" do
        result = source.fetch([product, other_product])

        expect(result.first).to match_array([mapping, mapping_for_other_integration])
        expect(result.second).to eq([other_mapping])
      end
    end
  end
end
