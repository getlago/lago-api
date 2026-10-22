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

  describe "check constraints" do
    subject(:insert) { aggregation.save(validate: false) }

    let(:organization) { create(:organization) }

    context "without a charge or a complete contract/product pair" do
      let(:aggregation) { build(:cached_aggregation, organization:, charge: nil) }

      it do
        expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*cached_aggregations_identity_present/)
      end
    end

    context "with a charge identity" do
      let(:charge) { create(:standard_charge, organization:) }
      let(:aggregation) { build(:cached_aggregation, organization:, charge:) }

      it { expect(insert).to be(true) }
    end

    context "with a complete contract/product identity" do
      let(:contract) { create(:contract, organization:) }
      let(:product) { create(:product, organization:) }
      let(:aggregation) { build(:cached_aggregation, organization:, charge: nil, contract:, product:) }

      it { expect(insert).to be(true) }
    end

    context "with only a contract" do
      let(:contract) { create(:contract, organization:) }
      let(:aggregation) { build(:cached_aggregation, organization:, charge: nil, contract:) }

      it do
        expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*cached_aggregations_identity_present/)
      end
    end

    context "with only a product" do
      let(:product) { create(:product, organization:) }
      let(:aggregation) { build(:cached_aggregation, organization:, charge: nil, product:) }

      it do
        expect { insert }.to raise_error(ActiveRecord::StatementInvalid, /PG::CheckViolation.*cached_aggregations_identity_present/)
      end
    end
  end
end
