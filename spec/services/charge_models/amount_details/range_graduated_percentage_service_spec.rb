# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::AmountDetails::RangeGraduatedPercentageService do
  subject(:details) { described_class.call(range:, units:) }

  let(:units) { 4 }
  let(:range) do
    {
      from_value: 7,
      to_value: 10,
      rate: "2.9",
      flat_amount: "2"
    }
  end

  it "returns expected amount details" do
    expect(details).to eq(
      {
        from_value: 7,
        to_value: 10,
        flat_unit_amount: 2,
        rate: 2.9,
        units: "4.0",
        per_unit_total_amount: "0.116",
        total_with_flat_amount: 2.116
      }
    )
  end

  context "with zero units" do
    let(:units) { 0 }
    let(:range) do
      {
        from_value: 0,
        to_value: 10,
        rate: "2.9",
        flat_amount: "2"
      }
    end

    it "applies the flat amount from the range" do
      expect(details).to eq(
        {
          from_value: 0,
          to_value: 10,
          flat_unit_amount: 2,
          rate: 2.9,
          units: "0.0",
          per_unit_total_amount: "0.0",
          total_with_flat_amount: 2
        }
      )
    end
  end

  context "with a partially filled tier" do
    let(:units) { 5 }
    let(:range) do
      {
        from_value: 11,
        to_value: 20,
        rate: "1",
        flat_amount: "1"
      }
    end

    it "returns expected amount details" do
      expect(details).to eq(
        {
          from_value: 11,
          to_value: 20,
          flat_unit_amount: 1,
          rate: 1,
          units: "5.0",
          per_unit_total_amount: "0.05",
          total_with_flat_amount: 1.05
        }
      )
    end
  end
end
