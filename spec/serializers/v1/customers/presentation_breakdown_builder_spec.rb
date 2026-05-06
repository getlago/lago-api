# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Customers::PresentationBreakdownBuilder do
  subject(:result) { described_class.call(fees, filter:) }

  let(:breakdown_class) { Struct.new(:presentation_by, :units, keyword_init: true) }
  let(:fee_class) { Struct.new(:presentation_breakdowns, :grouped_by, keyword_init: true) }
  let(:filter) { described_class::UNGROUPED }

  let(:fees) do
    [
      fee_class.new(
        grouped_by: nil,
        presentation_breakdowns: [
          breakdown_class.new(presentation_by: {"cloud" => "aws"}, units: "1.2"),
          breakdown_class.new(presentation_by: {"cloud" => "gcp"}, units: "3")
        ]
      ),
      fee_class.new(
        grouped_by: nil,
        presentation_breakdowns: [
          breakdown_class.new(presentation_by: {"cloud" => "aws"}, units: "0.3")
        ]
      )
    ]
  end

  it "returns one entry per breakdown with stringified units" do
    expect(result).to eq([
      {presentation_by: {"cloud" => "aws"}, units: "1.2"},
      {presentation_by: {"cloud" => "gcp"}, units: "3"},
      {presentation_by: {"cloud" => "aws"}, units: "0.3"}
    ])
  end

  context "when a fee has no presentation_breakdowns" do
    let(:fees) { [fee_class.new(grouped_by: nil, presentation_breakdowns: [])] }

    it "returns an empty array" do
      expect(result).to eq([])
    end
  end

  describe "filtering" do
    let(:ungrouped_fee) do
      fee_class.new(
        grouped_by: nil,
        presentation_breakdowns: [breakdown_class.new(presentation_by: {"region" => "us"}, units: "1")]
      )
    end
    let(:grouped_fee) do
      fee_class.new(
        grouped_by: {"region" => "eu"},
        presentation_breakdowns: [breakdown_class.new(presentation_by: {"region" => "eu"}, units: "2")]
      )
    end
    let(:fees) { [ungrouped_fee, grouped_fee] }

    context "when filter is UNGROUPED" do
      let(:filter) { described_class::UNGROUPED }

      it "includes only fees with blank grouped_by" do
        expect(result).to eq([
          {presentation_by: {"region" => "us"}, units: "1"}
        ])
      end
    end

    context "when filter is GROUPED" do
      let(:filter) { described_class::GROUPED }

      it "includes only fees with present grouped_by" do
        expect(result).to eq([
          {presentation_by: {"region" => "eu"}, units: "2"}
        ])
      end
    end

    context "when filter is ALL" do
      let(:filter) { described_class::ALL }

      it "includes breakdowns from all fees regardless of grouped_by" do
        expect(result).to eq([
          {presentation_by: {"region" => "us"}, units: "1"},
          {presentation_by: {"region" => "eu"}, units: "2"}
        ])
      end
    end
  end
end
