# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::Validators::Schemas::OneOff do
  let(:document) do
    {
      "currency" => "EUR",
      "billing_items" => {
        "add_ons" => [
          {
            "id" => SecureRandom.uuid,
            "local_id" => "row-1",
            "payload" => {"units" => 1, "unit_amount_cents" => 10_000},
            "overrides" => {}
          }
        ]
      }
    }
  end

  describe "schema constants" do
    it "exposes frozen, string-keyed schemas" do
      expect(described_class::UPDATE_SCHEMA).to be_frozen
      expect(described_class::APPROVE_SCHEMA).to be_frozen
      expect(described_class::UPDATE_SCHEMA.keys).to all(be_a(String))
      expect(described_class::APPROVE_SCHEMA.keys).to all(be_a(String))
    end
  end

  describe ".for" do
    it "returns the approve schema only for the approve scope" do
      expect(described_class.for(:approve)).to eq(described_class::APPROVE)
      expect(described_class.for(:update)).to eq(described_class::UPDATE)
    end
  end

  describe "UPDATE schema" do
    subject(:schema) { described_class::UPDATE }

    it "accepts a well-formed document" do
      expect(schema.valid?(document)).to eq(true)
    end

    it "accepts an incomplete draft" do
      document["currency"] = nil
      document["billing_items"] = {"add_ons" => [{"payload" => {"units" => nil}, "overrides" => {}}]}

      expect(schema.valid?(document)).to eq(true)
    end

    it "accepts BigDecimal units as a number" do
      document["billing_items"]["add_ons"][0]["payload"]["units"] = BigDecimal("1.5")

      expect(schema.valid?(document)).to eq(true)
    end

    it "rejects an unknown currency with value_is_invalid" do
      document["currency"] = "ABC"

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["value_is_invalid"])
    end

    it "rejects unexpected billing_items keys with value_is_invalid" do
      document["billing_items"]["extra"] = 1

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["value_is_invalid"])
    end

    it "rejects non-positive units with value_is_invalid" do
      document["billing_items"]["add_ons"][0]["payload"]["units"] = 0

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["value_is_invalid"])
    end

    it "rejects non-object payloads" do
      document["billing_items"]["add_ons"][0]["payload"] = "bad"

      expect(schema.valid?(document)).to eq(false)
    end
  end

  describe "APPROVE schema" do
    subject(:schema) { described_class::APPROVE }

    it "accepts a complete document" do
      expect(schema.valid?(document)).to eq(true)
    end

    it "rejects a nil currency with value_is_mandatory" do
      document["currency"] = nil

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["value_is_mandatory"])
    end

    it "rejects billing_items without add_ons with add_ons_required" do
      document["billing_items"] = {}

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["add_ons_required"])
    end

    it "rejects empty add_ons with add_ons_required" do
      document["billing_items"]["add_ons"] = []

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["add_ons_required"])
    end

    it "rejects a payload without units with value_is_mandatory" do
      document["billing_items"]["add_ons"][0]["payload"].delete("units")

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["value_is_mandatory"])
    end

    it "rejects nil units with a single value_is_mandatory error" do
      document["billing_items"]["add_ons"][0]["payload"]["units"] = nil

      expect(schema.validate(document).map { |e| e["error"] }).to eq(["value_is_mandatory"])
    end
  end
end
