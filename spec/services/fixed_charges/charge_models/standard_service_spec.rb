# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::ChargeModels::StandardService, type: :service do
  subject(:apply_standard_service) do
    described_class.apply(
      fixed_charge:,
      aggregation_result:,
      properties: fixed_charge.properties
    )
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:fixed_charge) { create(:fixed_charge, :standard, properties: {amount: "31.00"}) }

  before do
    aggregation_result.aggregation = aggregation
    aggregation_result.full_units_number = full_units_number
  end

  context "when fixed charge is not prorated" do
    let(:fixed_charge) { create(:fixed_charge, :standard, prorated: false, properties: {amount: "31.00"}) }
    let(:aggregation) { 1 }
    let(:full_units_number) { 1 }

    it "calculates amount as units * amount" do
      expect(apply_standard_service.amount).to eq(31.00)
      expect(apply_standard_service.unit_amount).to eq(31.00)
    end
  end

  context "when fixed charge is prorated" do
    let(:fixed_charge) { create(:fixed_charge, :standard, prorated: true, properties: {amount: "31.00"}) }

    context "with subscription starting May 10 and renewing June 1 (22 days)" do
      let(:aggregation) { 0.71 } # 22/31 ≈ 0.71 (prorated units)
      let(:full_units_number) { 1 } # Full period units

      it "calculates prorated amount correctly" do
        # Formula: aggregated units * full amount
        # 0.71 * 31.00 = 22.01
        # it should be 22 but aggregation leads to decimals
        # so we maybe look for a better way to handle this with a better aggregation service
        # we are calculating prorated units instead of amount per day then units * amount.
        expect(apply_standard_service.amount).to eq(22.01)
        expect(apply_standard_service.unit_amount).to eq(22.01)
      end
    end

    context "with subscription starting May 1 and renewing June 1 (31 days)" do
      let(:aggregation) { 1.0 } # 31/31 = 1.0 (prorated units)
      let(:full_units_number) { 1 } # Full period units

      it "calculates full amount" do
        # Formula: 1.0 * 31.00 = 31.00
        expect(apply_standard_service.amount).to eq(31.00)
        expect(apply_standard_service.unit_amount).to eq(31.00)
      end
    end

    context "with multiple units" do
      let(:aggregation) { 0.71 } # 22/31 ≈ 0.71 (prorated units)
      let(:full_units_number) { 2 } # Full period units

      it "calculates prorated amount for multiple units" do
        # Formula: 0.71 * 31.00 = 22.01
        expect(apply_standard_service.amount).to eq(22.01)
        expect(apply_standard_service.unit_amount).to eq(11.005) # 22.01 / 2
      end
    end

    context "with zero units" do
      let(:aggregation) { 0 }
      let(:full_units_number) { 0 }

      it "returns zero amount" do
        expect(apply_standard_service.amount).to eq(0)
        expect(apply_standard_service.unit_amount).to eq(0)
      end
    end
  end

  context "with different amounts" do
    let(:fixed_charge) { create(:fixed_charge, :standard, prorated: true, properties: {amount: "100.00"}) }
    let(:aggregation) { 0.5 } # 50% proration
    let(:full_units_number) { 1 }

    it "calculates prorated amount correctly" do
      # Formula: 0.5 * 100.00 = 50.00
      expect(apply_standard_service.amount).to eq(50.00)
      expect(apply_standard_service.unit_amount).to eq(50.00)
    end
  end
end
