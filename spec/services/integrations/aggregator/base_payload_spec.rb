# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::BasePayload do
  subject(:payload) { described_class.new(integration:, billing_entity:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:integration) { create(:anrok_integration, organization:) }
  let(:product) { create(:product, organization:) }

  describe "Product mapping fallback" do
    let!(:fallback_mapping) do
      create(
        :anrok_collection_mapping,
        integration:,
        organization:,
        mapping_type: :fallback_item
      )
    end

    it "returns the integration fallback when the Product has no mapping" do
      mapping = payload.send(:lookup_mapping, "Product", product.id)

      expect(mapping).to eq(fallback_mapping)
    end
  end
end
