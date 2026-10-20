# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::RateCardSerializer do
  let(:organization) { create(:organization) }

  describe "product parent" do
    let(:rate_card) { create(:rate_card, organization:) }
    let(:product) { rate_card.product }
    let(:reloaded_rate_card) { RateCard.with_discarded.find(rate_card.id) }

    it "keeps the product code when its parent is kept" do
      expect(described_class.new(rate_card).serialize[:product_code]).to eq(product.code)
    end

    context "when the optional product filter is absent" do
      let(:rate_card) { create(:rate_card, organization:, product_filter: nil) }

      it "keeps the product filter code nil" do
        expect(described_class.new(rate_card).serialize[:product_filter_code]).to be_nil
      end
    end

    context "when the product filter is discarded" do
      let(:rate_card) { create(:rate_card, :with_filter, organization:) }
      let(:product_filter) { rate_card.product_filter }

      before { product_filter.discard! }

      it "serializes the discarded product filter code" do
        expect(described_class.new(reloaded_rate_card).serialize[:product_filter_code]).to eq(product_filter.code)
      end
    end

    context "when the product parent is discarded" do
      before { product.discard! }

      it "serializes the reloaded rate card with the discarded product code" do
        expect(described_class.new(reloaded_rate_card).serialize[:product_code]).to eq(product.code)
      end
    end
  end

  describe V2::PlanRateCardSerializer do
    let(:catalog_plan) { create(:catalog_plan, organization:) }
    let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:) }
    let(:reloaded_plan_rate_card) { PlanRateCard.with_discarded.find(plan_rate_card.id) }
    let(:payload) { described_class.new(reloaded_plan_rate_card).serialize }

    it "keeps both parent codes when the parents are kept" do
      expect(described_class.new(plan_rate_card).serialize.values_at(:plan_code, :rate_card_code)).to eq([
        catalog_plan.code,
        plan_rate_card.rate_card.code
      ])
    end

    context "when the catalog plan parent is discarded" do
      before { catalog_plan.discard! }

      it "serializes both parent codes" do
        expect(payload.values_at(:plan_code, :rate_card_code)).to eq([catalog_plan.code, plan_rate_card.rate_card.code])
      end
    end

    context "when the rate card parent is discarded" do
      before { plan_rate_card.rate_card.discard! }

      it "serializes the discarded rate card code" do
        expect(payload[:rate_card_code]).to eq(plan_rate_card.rate_card.code)
      end
    end
  end

  describe V2::ContractAppliedRateCardSerializer do
    let(:contract_rate_card) { create(:contract_rate_card, organization:) }
    let(:payload) { described_class.new(contract_rate_card).serialize }
    let(:reloaded_contract_rate_card) { ContractRateCard.with_discarded.find(contract_rate_card.id) }

    it "keeps the contract and rate card parent values when present" do
      expect(payload.values_at(:external_contract_id, :rate_card_code)).to eq([
        contract_rate_card.contract.external_id,
        contract_rate_card.rate_card.code
      ])
    end

    context "when the rate card parent is discarded" do
      before { contract_rate_card.rate_card.discard! }

      it "serializes the discarded rate card code" do
        expect(described_class.new(reloaded_contract_rate_card).serialize[:rate_card_code]).to eq(contract_rate_card.rate_card.code)
      end
    end
  end
end
