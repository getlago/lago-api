# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageFilters do
  describe "#initialize" do
    it "sets default values" do
      filters = described_class.new

      expect(filters.filter_by_charge_id).to be_nil
      expect(filters.filter_by_charge_code).to be_nil
      expect(filters.filter_by_group).to be_nil
      expect(filters.skip_grouping).to be(false)
      expect(filters.full_usage).to be(false)
    end

    it "normalizes filter_by_group values to arrays" do
      filters = described_class.new(filter_by_group: {"cloud" => "aws", "region" => ["eu"]})

      expect(filters.filter_by_group).to eq({"cloud" => ["aws"], "region" => ["eu"]})
    end

    it "handles nil filter_by_group" do
      filters = described_class.new(filter_by_group: nil)

      expect(filters.filter_by_group).to be_nil
    end

    it "stores all provided values" do
      filters = described_class.new(
        filter_by_charge_id: "charge-id",
        filter_by_charge_code: "charge-code",
        filter_by_group: {"cloud" => ["aws"]},
        skip_grouping: true,
        full_usage: true
      )

      expect(filters.filter_by_charge_id).to eq("charge-id")
      expect(filters.filter_by_charge_code).to eq("charge-code")
      expect(filters.filter_by_group).to eq({"cloud" => ["aws"]})
      expect(filters.skip_grouping).to be(true)
      expect(filters.full_usage).to be(true)
    end
  end

  describe ".init_from_params" do
    it "builds filters from params" do
      params = {
        filter_by_charge_id: "charge-id",
        filter_by_charge_code: "charge-code",
        filter_by_group: {cloud: "aws"},
        skip_grouping: "true",
        full_usage: "true"
      }

      filters = described_class.init_from_params(params)

      expect(filters.filter_by_charge_id).to eq("charge-id")
      expect(filters.filter_by_charge_code).to eq("charge-code")
      expect(filters.filter_by_group).to eq({cloud: ["aws"]})
      expect(filters.skip_grouping).to be(true)
      expect(filters.full_usage).to be(true)
    end

    it "handles missing params with defaults" do
      params = {}

      filters = described_class.init_from_params(params)

      expect(filters.filter_by_charge_id).to be_nil
      expect(filters.filter_by_charge_code).to be_nil
      expect(filters.filter_by_group).to be_nil
      expect(filters.skip_grouping).to be_nil
      expect(filters.full_usage).to be_nil
    end
  end

  describe "NONE" do
    it "is a frozen instance with default values" do
      expect(described_class::NONE).to be_frozen
      expect(described_class::NONE.filter_by_charge_id).to be_nil
      expect(described_class::NONE.filter_by_charge_code).to be_nil
      expect(described_class::NONE.filter_by_group).to be_nil
      expect(described_class::NONE.skip_grouping).to be(false)
      expect(described_class::NONE.full_usage).to be(false)
    end
  end
end
