# frozen_string_literal: true

require "rails_helper"

RSpec.describe CachedAggregation do
  subject(:cached_aggregation) { build(:cached_aggregation) }

  let(:cached_aggregation_without_charge) { build(:cached_aggregation, charge: nil) }
  let(:contract) { build(:contract) }
  let(:product) { build(:product, organization: contract.organization) }
  let(:contract_aggregation) { build(:cached_aggregation, charge: nil, contract:, product:) }
  let(:contract_aggregation_without_product) { build(:cached_aggregation, charge: nil, contract:) }
  let(:contract_aggregation_without_contract) { build(:cached_aggregation, charge: nil, product:) }

  describe "associations" do
    it "belongs to its organization and optional charge identity" do
      expect(cached_aggregation).to belong_to(:organization)
      expect(cached_aggregation).to belong_to(:contract).optional
      expect(cached_aggregation).to belong_to(:group).optional
      expect(cached_aggregation).to belong_to(:charge_filter).optional

      # Charge is optional on the association but conditionally required for legacy aggregations.
      {
        charge: {foreign_key: "charge_id", scope: false},
        product: {foreign_key: "product_id", scope: true},
        product_filter: {foreign_key: "product_filter_id", scope: true}
      }.each do |name, expected|
        association = described_class.reflect_on_association(name)
        expect(association.macro).to eq(:belongs_to)
        expect(association.foreign_key).to eq(expected[:foreign_key])
        expect(association.options).to include(optional: true)
        expect(association.scope.present?).to eq(expected[:scope])
      end
    end
  end

  describe "validations" do
    it "requires a charge for legacy aggregation and a product/contract pair for contract aggregation" do
      expect(cached_aggregation).to be_valid
      expect(cached_aggregation_without_charge).not_to be_valid
      expect(contract_aggregation).to be_valid
      expect(contract_aggregation_without_product).not_to be_valid
      expect(contract_aggregation_without_contract).not_to be_valid
    end
  end
end
