# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::ObfuscatedStringType do
  describe ".coerce_result" do
    it "keeps only the last 3 characters" do
      expect(described_class.coerce_result("secret_value_123", {})).to eq("••••••••…123")
    end

    it "returns nil for a nil value" do
      expect(described_class.coerce_result(nil, {})).to be_nil
    end
  end

  describe ".obfuscated?" do
    it "detects a masked value" do
      expect(described_class.obfuscated?(described_class.coerce_result("secret_value_123", {}))).to be(true)
    end

    it "does not flag a new value" do
      expect(described_class.obfuscated?("new_secret")).to be(false)
      expect(described_class.obfuscated?(nil)).to be(false)
    end
  end
end
