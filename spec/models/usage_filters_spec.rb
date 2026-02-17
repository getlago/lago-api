# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageFilters do
  describe "#initialize" do
    it "sets default values" do
      filters = described_class.new

      expect(filters.filter_by_charge).to be_nil
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
      charge = instance_double(Charge)
      filters = described_class.new(
        filter_by_charge: charge,
        filter_by_group: {"cloud" => ["aws"]},
        skip_grouping: true,
        full_usage: true
      )

      expect(filters.filter_by_charge).to eq(charge)
      expect(filters.filter_by_group).to eq({"cloud" => ["aws"]})
      expect(filters.skip_grouping).to be(true)
      expect(filters.full_usage).to be(true)
    end
  end

  describe "NONE" do
    it "is a frozen instance with default values" do
      expect(described_class::NONE).to be_frozen
      expect(described_class::NONE.filter_by_charge).to be_nil
      expect(described_class::NONE.filter_by_group).to be_nil
      expect(described_class::NONE.skip_grouping).to be(false)
      expect(described_class::NONE.full_usage).to be(false)
    end
  end
end
