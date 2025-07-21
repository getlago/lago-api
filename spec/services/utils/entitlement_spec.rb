# frozen_string_literal: true

require "rails_helper"

RSpec.describe Utils::Entitlement do
  subject(:utils_entitlement) { described_class }

  describe ".cast_value" do
    context "when value is blank" do
      it "returns nil for empty string" do
        expect(utils_entitlement.cast_value("", "integer")).to be_nil
      end

      it "returns nil for nil" do
        expect(utils_entitlement.cast_value(nil, "integer")).to be_nil
      end
    end

    context "when type is integer" do
      it "casts string to integer" do
        expect(utils_entitlement.cast_value("42", "integer")).to eq(42)
      end

      it "casts float string to integer" do
        expect(utils_entitlement.cast_value("42.5", "integer")).to eq(42)
      end
    end

    context "when type is boolean" do
      it "casts true string to boolean" do
        expect(utils_entitlement.cast_value("true", "boolean")).to be(true)
      end

      it "casts false string to boolean" do
        expect(utils_entitlement.cast_value("false", "boolean")).to be(false)
      end

      it "casts 1 to boolean" do
        expect(utils_entitlement.cast_value("1", "boolean")).to be(true)
      end

      it "casts 0 to boolean" do
        expect(utils_entitlement.cast_value("0", "boolean")).to be(false)
      end
    end

    context "when type is string or unknown" do
      it "returns value as-is for string type" do
        expect(utils_entitlement.cast_value("hello", "string")).to eq("hello")
      end

      it "returns value as-is for unknown type" do
        expect(utils_entitlement.cast_value("hello", "unknown")).to eq("hello")
      end
    end
  end
end
