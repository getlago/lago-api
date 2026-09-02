# frozen_string_literal: true

require "rails_helper"

RSpec.describe Integrations::Aggregator::BasePayload do
  subject(:payload) { described_class.new(integration:, billing_entity:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:) }
  let(:integration) { create(:anrok_integration, organization:) }
  let(:product) { create(:product, organization:) }
  let(:fee) { instance_double(Fee, invoiceable_id: product.id) }

  describe "Product mapping lookup" do
    it "returns the Billing Entity Product mapping" do
      create(:anrok_mapping, integration:, organization:, mappable: product)
      product_mapping = create(:anrok_mapping, integration:, organization:, billing_entity:, mappable: product)

      expect(payload.product_item(fee)).to eq(product_mapping)
    end

    it "returns the organization Product mapping when no Billing Entity mapping exists" do
      product_mapping = create(:anrok_mapping, integration:, organization:, mappable: product)

      expect(payload.product_item(fee)).to eq(product_mapping)
    end

    it "returns the Billing Entity fallback when the Product has no mapping" do
      create(:anrok_collection_mapping, integration:, organization:, mapping_type: :fallback_item)
      fallback_mapping = create(
        :anrok_collection_mapping,
        integration:,
        organization:,
        billing_entity:,
        mapping_type: :fallback_item
      )

      expect(payload.product_item(fee)).to eq(fallback_mapping)
    end

    it "returns the organization fallback when no Product or Billing Entity mapping exists" do
      fallback_mapping = create(
        :anrok_collection_mapping,
        integration:,
        organization:,
        mapping_type: :fallback_item
      )

      expect(payload.product_item(fee)).to eq(fallback_mapping)
    end
  end
end
