# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::AmountDetails::RangeGraduatedService do
  subject(:service) { described_class.new(range:, total_units:) }

  let(:total_units) { 15 }
  let(:range) do
    {
      from_value: 0,
      to_value: 10,
      per_unit_amount: "10",
      flat_amount: "2"
    }
  end

  it "returns expected amount details" do
    expect(service.call).to eq(
      {
        from_value: 0,
        to_value: 10,
        flat_unit_amount: 2,
        per_unit_amount: 10,
        units: "10.0",
        per_unit_total_amount: 100,
        total_with_flat_amount: 102
      }
    )
  end

  context "when total units <= range to_value" do
    let(:range) do
      {
        from_value: 11,
        to_value: 20,
        per_unit_amount: "8",
        flat_amount: "1"
      }
    end

    it "returns expected amount details" do
      expect(service.call).to eq(
        {
          from_value: 11,
          to_value: 20,
          flat_unit_amount: 1,
          per_unit_amount: 8,
          units: "5.0",
          per_unit_total_amount: 40,
          total_with_flat_amount: 41
        }
      )
    end
  end
end
