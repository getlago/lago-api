# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::ChargeModels::GraduatedService, type: :service do
  subject(:apply_graduated_service) do
    described_class.apply(
      fixed_charge:,
      aggregation_result:,
      properties: fixed_charge.properties
    )
  end

  let(:aggregation_result) { BaseService::Result.new }
  let(:graduated_ranges) do
    [
      {from_value: 0, to_value: 10, per_unit_amount: "2", flat_amount: "1"},
      {from_value: 11, to_value: nil, per_unit_amount: "1", flat_amount: "0"}
    ]
  end

  let(:fixed_charge) do
    create(
      :fixed_charge,
      charge_model: "graduated",
      properties: {graduated_ranges:}
    )
  end

  before do
    aggregation_result.aggregation = aggregation
  end

  context "when aggregation is zero" do
    let(:aggregation) { 0 }

    it "applies the model to the values" do
      expect(apply_graduated_service.amount).to eq(0)
      expect(apply_graduated_service.unit_amount).to eq(0)
      expect(apply_graduated_service.amount_details).to eq(
        {
          graduated_ranges: [
            flat_unit_amount: 0,
            from_value: 0,
            to_value: 10,
            per_unit_total_amount: 0,
            total_with_flat_amount: 0,
            per_unit_amount: 0,
            units: "0.0"
          ]
        }
      )
    end
  end

  context "when aggregation is within first range" do
    let(:aggregation) { 5 }

    it "applies the model to the values" do
      expect(apply_graduated_service.amount).to eq(11)
      expect(apply_graduated_service.unit_amount).to eq(2.2)
      expect(apply_graduated_service.amount_details).to eq(
        graduated_ranges: [
          {
            from_value: 0,
            to_value: 10,
            flat_unit_amount: 1,
            per_unit_amount: 2,
            per_unit_total_amount: 10,
            total_with_flat_amount: 11,
            units: "5.0"
          },
        ]
      )
  
    end
  end

  context "when aggregation is 16" do
    let(:aggregation) { 16 }

    it "applies the model to the values" do
      expect(apply_graduated_service.amount).to eq(27)
      expect(apply_graduated_service.unit_amount).to eq(1.6875)

      expect(apply_graduated_service.amount_details).to eq(
        graduated_ranges: [
          {
            from_value: 0,
            to_value: 10,
            flat_unit_amount: 1,
            per_unit_amount: 2,
            per_unit_total_amount: 20,
            total_with_flat_amount: 21,
            units: "10.0"
          },
          {
            from_value: 11,
            to_value: nil,
            flat_unit_amount: 0,
            per_unit_amount: 1,
            per_unit_total_amount: 6,
            total_with_flat_amount: 6,
            units: "6.0"
          }
        ]
      )
    end
  end
end 