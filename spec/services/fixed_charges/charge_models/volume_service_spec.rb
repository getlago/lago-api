# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::ChargeModels::VolumeService, type: :service do
  subject(:apply_volume_service) do
    described_class.apply(
      fixed_charge:,
      aggregation_result:,
      properties: fixed_charge.properties
    )
  end

  before do
    aggregation_result.aggregation = aggregation
  end

  let(:aggregation_result) { BaseService::Result.new }

  let(:fixed_charge) do
    create(
      :fixed_charge,
      charge_model: "volume",
      properties: {
        volume_ranges: [
          {from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "10"},
          {from_value: 101, to_value: 200, per_unit_amount: "1", flat_amount: "0"},
          {from_value: 201, to_value: nil, per_unit_amount: "0.5", flat_amount: "50"}
        ]
      }
    )
  end

  context "when aggregation is 0" do
    let(:aggregation) { 0 }

    it "does not apply the flat amount" do
      expect(apply_volume_service.amount).to eq(0)
      expect(apply_volume_service.unit_amount).to eq(0)
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 0.0,
          per_unit_amount: 0.0,
          per_unit_total_amount: 0.0
        }
      )
    end
  end

  context "when aggregation is 1" do
    let(:aggregation) { 1 }

    it "applies the first tier rate to all units plus flat amount" do
      expect(apply_volume_service.amount).to eq(12) # 1 * 2 + 10
      expect(apply_volume_service.unit_amount).to eq(12) # 12 / 1
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 10,
          per_unit_amount: "2.0",
          per_unit_total_amount: 2
        }
      )
    end
  end

  context "when aggregation is the limit of the first range" do
    let(:aggregation) { 100 }

    it "applies the first tier rate to all units plus flat amount" do
      expect(apply_volume_service.amount).to eq(210) # 100 * 2 + 10
      expect(apply_volume_service.unit_amount).to eq(2.1) # 210 / 100
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 10,
          per_unit_amount: "2.0",
          per_unit_total_amount: 200
        }
      )
    end
  end

  context "when aggregation is in the between of first and second range" do
    let(:aggregation) { 100.5 }

    it "applies the second tier rate to all units plus flat amount" do
      expect(apply_volume_service.amount).to eq(100.5) # 100.5 * 1 + 0
      expect(apply_volume_service.unit_amount).to eq(1) # 100.5 / 100.5
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 0,
          per_unit_amount: "1.0",
          per_unit_total_amount: 100.5
        }
      )
    end
  end

  context "when aggregation is the lower limit of the second range" do
    let(:aggregation) { 101 }

    it "applies the second tier rate to all units plus flat amount" do
      expect(apply_volume_service.amount).to eq(101) # 101 * 1 + 0
      expect(apply_volume_service.unit_amount).to eq(1) # 101 / 101
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 0,
          per_unit_amount: "1.0",
          per_unit_total_amount: 101
        }
      )
    end
  end

  context "when aggregation is the upper limit of the second range" do
    let(:aggregation) { 200 }

    it "applies the second tier rate to all units plus flat amount" do
      expect(apply_volume_service.amount).to eq(200) # 200 * 1 + 0
      expect(apply_volume_service.unit_amount).to eq(1) # 200 / 200
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 0,
          per_unit_amount: "1.0",
          per_unit_total_amount: 200
        }
      )
    end
  end

  context "when aggregation is above the lower limit of the last range" do
    let(:aggregation) { 300 }

    it "applies the third tier rate to all units plus flat amount" do
      expect(apply_volume_service.amount).to eq(200) # 300 * 0.5 + 50
      expect(apply_volume_service.unit_amount.round(2)).to eq(0.67) # 200 / 300
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 50,
          per_unit_amount: "0.5",
          per_unit_total_amount: 150
        }
      )
    end
  end

  context "when charge is prorated" do
    let(:aggregation) { 198.6 }
    let(:fixed_charge) do
      create(
        :fixed_charge,
        charge_model: "volume",
        properties: {
          volume_ranges: [
            {from_value: 0, to_value: 100, per_unit_amount: "2", flat_amount: "10"},
            {from_value: 101, to_value: 200, per_unit_amount: "1", flat_amount: "0"},
            {from_value: 201, to_value: nil, per_unit_amount: "0.5", flat_amount: "50"}
          ]
        },
        prorated: true
      )
    end

    before do
      aggregation_result.full_units_number = 300
    end

    it "applies unit amount the third range" do
      expect(apply_volume_service.amount).to eq(149.3)
      expect(apply_volume_service.unit_amount.round(2)).to eq(0.50)
      expect(apply_volume_service.amount_details).to eq(
        {
          flat_unit_amount: 50,
          per_unit_amount: "0.331",
          per_unit_total_amount: 99.3
        }
      )
    end
  end
end
