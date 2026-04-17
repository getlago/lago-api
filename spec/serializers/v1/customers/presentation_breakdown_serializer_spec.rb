# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::V1::Customers::PresentationBreakdownSerializer do
  subject(:result) { described_class.call(fees) }

  let(:breakdown_class) { Struct.new(:presentation_by, :units, keyword_init: true) }
  let(:fee_class) { Struct.new(:presentation_breakdowns, keyword_init: true) }

  let(:fees) do
    [
      fee_class.new(
        presentation_breakdowns: [
          breakdown_class.new(presentation_by: {"cloud" => "aws"}, units: "1.2"),
          breakdown_class.new(presentation_by: {"cloud" => "gcp"}, units: 3)
        ]
      ),
      fee_class.new(
        presentation_breakdowns: [
          breakdown_class.new(presentation_by: {"cloud" => "aws"}, units: BigDecimal("0.3"))
        ]
      )
    ]
  end

  it "sums units per presentation_by and stringifies units" do
    expect(result).to match_array([
      {presentation_by: {"cloud" => "aws"}, units: "1.5"},
      {presentation_by: {"cloud" => "gcp"}, units: "3.0"}
    ])
  end

  context "when a fee has nil presentation_breakdowns" do
    let(:fees) { [fee_class.new(presentation_breakdowns: [])] }

    it "returns an empty array" do
      expect(result).to eq([])
    end
  end
end
