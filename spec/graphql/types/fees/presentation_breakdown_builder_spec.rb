# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Fees::PresentationBreakdownBuilder do
  subject(:result) { described_class.call(fees) }

  let(:fees) { [fee_one, fee_two] }

  let(:fee_one) do
    build(
      :charge_fee,
      presentation_breakdowns: [
        build(
          :presentation_breakdown,
          fee: nil,
          presentation_by: {"cloud" => "aws"},
          units: 1.2
        )
      ]
    )
  end

  let(:fee_two) do
    build(
      :charge_fee,
      invoice: fee_one.invoice,
      presentation_breakdowns: [
        build(
          :presentation_breakdown,
          presentation_by: {"cloud" => "aws"},
          units: 0.3
        ),
        build(
          :presentation_breakdown,
          presentation_by: {"cloud" => "gcp"},
          units: 3
        )
      ]
    )
  end

  it "groups by presentation_by and sums units across fees" do
    expect(result).to match_array([
      {presentation_by: {"cloud" => "aws"}, units: "1.5"},
      {presentation_by: {"cloud" => "gcp"}, units: "3.0"}
    ])
  end

  context "when fees contain nil presentation_breakdowns" do
    let(:fees) { [build(:charge_fee, presentation_breakdowns: [])] }

    it "returns an empty array" do
      expect(result).to eq([])
    end
  end
end
