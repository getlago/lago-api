# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateProperties::NormalizeRangesService do
  subject(:result) { described_class.call(rate_properties:) }

  let(:rate_properties) { {"amount" => "1", "graduated_ranges" => ranges} }
  let(:ranges) do
    [
      {"to_value" => "10", "flat_amount" => "10", "per_unit_amount" => "0.5"},
      {"to_value" => "20.5", "flat_amount" => "10", "per_unit_amount" => "0.5"},
      {"to_value" => nil, "flat_amount" => "0", "per_unit_amount" => "0.4"}
    ]
  end

  it "starts each tier where the previous one ends" do
    expect(result).to be_success
    expect(result.rate_properties["graduated_ranges"].map { it.values_at("from_value", "to_value") })
      .to eq([[0, 10], [10, 20.5], [20.5, nil]])
    expect(result.rate_properties["amount"]).to eq("1")
  end

  context "with numeric upper bounds" do
    let(:ranges) { [{"to_value" => 10, "flat_amount" => "0", "per_unit_amount" => "1"}, {"to_value" => nil, "flat_amount" => "0", "per_unit_amount" => "1"}] }

    it "accepts them" do
      expect(result.rate_properties["graduated_ranges"].map { it["from_value"] }).to eq([0, 10])
    end
  end

  %w[graduated_percentage_ranges volume_ranges].each do |key|
    context "with #{key}" do
      let(:rate_properties) { {key => [{"to_value" => "5", "flat_amount" => "0"}, {"to_value" => nil, "flat_amount" => "0"}]} }

      it "derives the lower bounds too" do
        expect(result.rate_properties[key].map { it.values_at("from_value", "to_value") }).to eq([[0, 5], [5, nil]])
      end
    end
  end

  context "without tiers" do
    let(:rate_properties) { {"amount" => "1"} }

    it "leaves the properties as they are" do
      expect(result.rate_properties).to eq("amount" => "1")
    end
  end

  context "when a tier names its lower bound" do
    let(:ranges) { [{"from_value" => 0, "to_value" => "10"}, {"to_value" => nil}] }

    it "rejects it" do
      expect(result).not_to be_success
      expect(result.error.messages[:graduated_ranges]).to eq(["from_value_not_allowed"])
    end
  end

  {
    "when the upper bounds do not rise" => ["10", "10", nil],
    "when the last tier is closed" => ["10", "20"],
    "when a tier before the last is open" => [nil, "20", nil],
    "when an upper bound is not a number" => ["ten", nil],
    "when an upper bound is not positive" => ["0", nil],
    "when an upper bound is infinite" => ["10", "Infinity", nil],
    "when upper bounds only differ beyond float precision" => ["1.00000000000000001", "1.00000000000000002", nil]
  }.each do |description, bounds|
    context description do
      let(:ranges) { bounds.map { {"to_value" => it, "flat_amount" => "0", "per_unit_amount" => "1"} } }

      it "rejects the tiers" do
        expect(result).not_to be_success
        expect(result.error.messages[:graduated_ranges]).to eq(["invalid_graduated_ranges"])
      end
    end
  end
end
