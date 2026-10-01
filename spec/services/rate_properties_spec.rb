# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateProperties do
  describe ".present" do
    subject(:presented) { described_class.present(properties) }

    let(:properties) do
      {
        "amount" => "1",
        "volume_ranges" => [
          {"from_value" => 0, "to_value" => 10, "flat_amount" => "0", "per_unit_amount" => "1"},
          {"from_value" => 10, "to_value" => 20.5, "flat_amount" => "0", "per_unit_amount" => "1"},
          {"from_value" => 20.5, "to_value" => nil, "flat_amount" => "0", "per_unit_amount" => "1"}
        ]
      }
    end

    it "drops the lower bounds and shows the upper bounds as strings" do
      expect(presented["volume_ranges"].map { it["to_value"] }).to eq(["10", "20.5", nil])
      expect(presented["volume_ranges"].map(&:keys)).to all(eq(%w[to_value flat_amount per_unit_amount]))
      expect(presented["amount"]).to eq("1")
    end
  end
end
