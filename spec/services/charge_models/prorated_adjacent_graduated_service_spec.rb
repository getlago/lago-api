# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeModels::ProratedAdjacentGraduatedService do
  subject(:apply_service) { described_class.apply(pricing_structure:, aggregation_result:, period_ratio: 1.0) }

  let(:pricing_structure) do
    ChargeModels::PricingStructure.new(
      charge_model: "graduated",
      properties: {"graduated_ranges" => graduated_ranges},
      prorated: true,
      accepts_target_wallet: false,
      currency: Money::Currency.new("EUR"),
      product_catalog: true
    )
  end
  let(:graduated_ranges) do
    [
      {"from_value" => 0, "to_value" => 10, "per_unit_amount" => "1", "flat_amount" => "0"},
      {"from_value" => 10, "to_value" => 20, "per_unit_amount" => "2", "flat_amount" => "0"},
      {"from_value" => 20, "to_value" => nil, "per_unit_amount" => "3", "flat_amount" => "0"}
    ]
  end
  let(:full_units) { [15, -6] }
  let(:prorated_units) { full_units }
  let(:per_event_aggregation) do
    BillableMetrics::ProratedAggregations::BaseService::ProratedPerEventAggregationResult.new.tap do |r|
      r.event_aggregation = full_units
      r.event_prorated_aggregation = prorated_units
    end
  end
  let(:aggregator) { instance_double(BillableMetrics::ProratedAggregations::SumService, per_event_aggregation:) }
  let(:aggregation_result) do
    BillableMetrics::Aggregations::BaseService::Result.new.tap do |r|
      r.aggregator = aggregator
      r.aggregation = prorated_units.sum
      r.full_units_number = full_units.sum
    end
  end

  # 15 units, then 6 removed: the 5 in the second tier go first, then 1 of the first.
  it "empties the top tiers first on a decrease" do
    expect(apply_service.amount).to eq(9)
  end

  context "with a removal priced at its own proration" do
    let(:full_units) { [11, -2] }
    let(:prorated_units) { [11, -1] }

    # 10 x 1 + 1 x 2, less half of (1 x 2 + 1 x 1).
    it "takes the removed units back from the tiers they sat in" do
      expect(apply_service.amount).to eq(10.5)
    end
  end

  context "with a tier one unit wide and a second addition" do
    let(:graduated_ranges) do
      [
        {"from_value" => 0, "to_value" => 2, "per_unit_amount" => "1", "flat_amount" => "0"},
        {"from_value" => 2, "to_value" => 3, "per_unit_amount" => "2", "flat_amount" => "0"},
        {"from_value" => 3, "to_value" => nil, "per_unit_amount" => "3", "flat_amount" => "0"}
      ]
    end
    let(:full_units) { [5, 2] }

    # Units 1-2 at 1, unit 3 at 2, units 4-7 at 3.
    it "bills that unit at its own tier's price" do
      expect(apply_service.amount).to eq(16)
    end
  end

  context "with decimal bounds" do
    let(:graduated_ranges) do
      [
        {"from_value" => 0, "to_value" => 10.5, "per_unit_amount" => "1", "flat_amount" => "0"},
        {"from_value" => 10.5, "to_value" => nil, "per_unit_amount" => "2", "flat_amount" => "0"}
      ]
    end
    let(:full_units) { [12] }
    let(:prorated_units) { [6] }

    # Half of 10.5 x 1 + 1.5 x 2.
    it "splits the event at the decimal bound" do
      expect(apply_service.amount).to eq(6.75)
    end
  end

  context "with flat amounts" do
    let(:graduated_ranges) do
      [
        {"from_value" => 0, "to_value" => 10, "per_unit_amount" => "0", "flat_amount" => "100"},
        {"from_value" => 10, "to_value" => nil, "per_unit_amount" => "0", "flat_amount" => "50"}
      ]
    end

    context "when usage peaks exactly at a bound" do
      let(:full_units) { [10, -4] }

      it "charges the flat amounts of the tiers it reached" do
        expect(apply_service.amount).to eq(100)
      end
    end

    context "when usage peaks past a bound" do
      let(:full_units) { [10, 1, -4] }

      it "charges the next tier's flat amount too" do
        expect(apply_service.amount).to eq(150)
      end
    end
  end

  context "with tiers stored stepping by one unit" do
    let(:graduated_ranges) do
      [
        {"from_value" => 0, "to_value" => 10, "per_unit_amount" => "1", "flat_amount" => "0"},
        {"from_value" => 11, "to_value" => nil, "per_unit_amount" => "2", "flat_amount" => "0"}
      ]
    end
    let(:full_units) { [15] }

    # 10 x 1 + 5 x 2, as the step calculator counts them.
    it "prices them as step tiers" do
      expect(apply_service.amount).to eq(20)
    end
  end

  context "with a removal whose addition was left out" do
    let(:full_units) { [-1, 5] }
    let(:prorated_units) { [0, 5] }

    it "leaves the removal out of the tiers" do
      expect(apply_service.amount).to eq(5)
    end
  end

  context "with a unique count" do
    # Ids added for the time they stay, a removal carrying nothing.
    let(:full_units) { [1, 1, -1] }
    let(:prorated_units) { [0.5, 0.25, 0] }
    let(:graduated_ranges) do
      [
        {"from_value" => 0, "to_value" => 1, "per_unit_amount" => "10", "flat_amount" => "0"},
        {"from_value" => 1, "to_value" => nil, "per_unit_amount" => "1", "flat_amount" => "0"}
      ]
    end

    # The first id at 10 for half the period, the second at 1 for a quarter.
    it "keeps each id at the tier it entered" do
      expect(apply_service.amount).to eq(5.25)
    end

    context "when the ids fill three tiers before two leave" do
      let(:full_units) { [1, 1, 1, -1, -1] }
      let(:prorated_units) { [0.25, 1, 1, 0, 0] }
      let(:graduated_ranges) do
        [
          {"from_value" => 0, "to_value" => 1, "per_unit_amount" => "2", "flat_amount" => "0"},
          {"from_value" => 1, "to_value" => 2, "per_unit_amount" => "9", "flat_amount" => "0"},
          {"from_value" => 2, "to_value" => nil, "per_unit_amount" => "2", "flat_amount" => "0"}
        ]
      end

      # 2 x 0.25 + 9 x 1 + 2 x 1. The step calculator bills 18.5, pricing the third id
      # at the second tier.
      it "prices the third id at the tier it entered" do
        expect(apply_service.amount).to eq(11.5)
      end
    end
  end

  context "with an addition worth nothing in the period" do
    let(:full_units) { [10, 5] }
    let(:prorated_units) { [0, 5] }

    it "leaves it out of the tiers" do
      expect(apply_service.amount).to eq(5)
    end
  end
end
