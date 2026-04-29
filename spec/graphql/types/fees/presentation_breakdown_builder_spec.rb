# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Fees::PresentationBreakdownBuilder do
  subject(:result) { described_class.call(fees, filter:) }

  let(:filter) { described_class::UNGROUPED }
  let(:fees) { [fee_one, fee_two] }

  let(:fee_one) do
    build(
      :charge_fee,
      grouped_by: {},
      presentation_breakdowns: [
        build(:presentation_breakdown, fee: nil, presentation_by: {"cloud" => "aws"}, units: 1.2)
      ]
    )
  end

  let(:fee_two) do
    build(
      :charge_fee,
      invoice: fee_one.invoice,
      grouped_by: {},
      presentation_breakdowns: [
        build(:presentation_breakdown, presentation_by: {"cloud" => "aws"}, units: 0.3),
        build(:presentation_breakdown, presentation_by: {"cloud" => "gcp"}, units: 3)
      ]
    )
  end

  it "returns one entry per breakdown with stringified units" do
    expect(result).to eq([
      {presentation_by: {"cloud" => "aws"}, units: "1.2"},
      {presentation_by: {"cloud" => "aws"}, units: "0.3"},
      {presentation_by: {"cloud" => "gcp"}, units: "3.0"}
    ])
  end

  context "when fees contain no presentation_breakdowns" do
    let(:fees) { [build(:charge_fee, grouped_by: {}, presentation_breakdowns: [])] }

    it "returns an empty array" do
      expect(result).to eq([])
    end
  end

  describe "filtering" do
    let(:ungrouped_fee) do
      build(
        :charge_fee,
        grouped_by: {},
        presentation_breakdowns: [
          build(:presentation_breakdown, fee: nil, presentation_by: {"region" => "us"}, units: 1)
        ]
      )
    end

    let(:grouped_fee) do
      build(
        :charge_fee,
        grouped_by: {"region" => "eu"},
        presentation_breakdowns: [
          build(:presentation_breakdown, fee: nil, presentation_by: {"region" => "eu"}, units: 2)
        ]
      )
    end

    let(:fees) { [ungrouped_fee, grouped_fee] }

    context "when filter is UNGROUPED" do
      let(:filter) { described_class::UNGROUPED }

      it "includes only fees with blank grouped_by" do
        expect(result).to eq([
          {presentation_by: {"region" => "us"}, units: "1.0"}
        ])
      end
    end

    context "when filter is GROUPED" do
      let(:filter) { described_class::GROUPED }

      it "includes only fees with present grouped_by" do
        expect(result).to eq([
          {presentation_by: {"region" => "eu"}, units: "2.0"}
        ])
      end
    end

    context "when filter is ALL" do
      let(:filter) { described_class::ALL }

      it "includes breakdowns from all fees regardless of grouped_by" do
        expect(result).to eq([
          {presentation_by: {"region" => "us"}, units: "1.0"},
          {presentation_by: {"region" => "eu"}, units: "2.0"}
        ])
      end
    end
  end
end
