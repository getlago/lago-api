# frozen_string_literal: true

require "rails_helper"

RSpec.describe Utils::ChargeProperties do
  describe ".underscore_keys" do
    it "underscores the keys of a camelCase payload" do
      properties = {
        "graduatedRanges" => [
          {"fromValue" => 0, "toValue" => 1000, "perUnitAmount" => "0.005", "flatAmount" => "0"},
          {"fromValue" => 1001, "toValue" => nil, "perUnitAmount" => "0.002", "flatAmount" => "0"}
        ],
        "pricingGroupKeys" => %w[regionName cloudProvider]
      }

      expect(described_class.underscore_keys(properties)).to eq(
        {
          "graduated_ranges" => [
            {"from_value" => 0, "to_value" => 1000, "per_unit_amount" => "0.005", "flat_amount" => "0"},
            {"from_value" => 1001, "to_value" => nil, "per_unit_amount" => "0.002", "flat_amount" => "0"}
          ],
          "pricing_group_keys" => %w[regionName cloudProvider]
        }
      )
    end

    it "leaves an already underscored payload untouched" do
      properties = {
        "graduated_ranges" => [{"from_value" => 0, "to_value" => nil, "per_unit_amount" => "1", "flat_amount" => "0"}]
      }

      expect(described_class.underscore_keys(properties)).to eq(properties)
    end

    it "stringifies symbol keys" do
      expect(described_class.underscore_keys({freeUnits: 10, packageSize: 100}))
        .to eq({"free_units" => 10, "package_size" => 100})
    end

    # The customer defined those keys for their own aggregation, renaming them would change what it
    # reads at billing time.
    it "keeps the keys the customer defined inside custom_properties" do
      properties = {"customProperties" => {"myOwnKey" => {"nestedKey" => "value"}}}

      expect(described_class.underscore_keys(properties))
        .to eq({"custom_properties" => {"myOwnKey" => {"nestedKey" => "value"}}})
    end

    it "returns anything that is not an object as it arrived" do
      expect(described_class.underscore_keys(nil)).to be_nil
      expect(described_class.underscore_keys("graduatedRanges")).to eq("graduatedRanges")
      expect(described_class.underscore_keys([{"fromValue" => 0}])).to eq([{"fromValue" => 0}])
    end
  end
end
