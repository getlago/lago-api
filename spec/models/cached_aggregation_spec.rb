# frozen_string_literal: true

require "rails_helper"

RSpec.describe CachedAggregation do
  subject(:cached_aggregation) { build(:cached_aggregation) }

  describe "associations" do
    it "belongs to its organization and optional charge identity" do
      expected_options = {
        organization: {},
        charge: {optional: true},
        contract: {optional: true},
        product: {optional: true},
        product_filter: {optional: true},
        group: {optional: true},
        charge_filter: {optional: true}
      }

      expected_options.each do |name, options|
        association = described_class.reflect_on_association(name)
        expect(association.macro).to eq(:belongs_to)
        expect(association.options).to include(options)
      end

      expect(described_class.reflect_on_association(:product).scope).to be_present
      expect(described_class.reflect_on_association(:product_filter).scope).to be_present
    end
  end

  describe "validations" do
    it "requires a charge for legacy aggregation and a product/contract pair for contract aggregation" do
      expect(cached_aggregation).to be_valid
      expect(build(:cached_aggregation, charge: nil)).not_to be_valid

      contract = build(:contract)
      product = build(:product, organization: contract.organization)
      contract_aggregation = build(:cached_aggregation, charge: nil, contract:, product:)

      expect(contract_aggregation).to be_valid
      expect(build(:cached_aggregation, charge: nil, product:)).not_to be_valid
      expect(build(:cached_aggregation, charge: nil, contract:)).not_to be_valid
    end
  end
end
