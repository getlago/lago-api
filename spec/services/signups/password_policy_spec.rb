# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signups::PasswordPolicy do
  describe ".violations" do
    it "accepts a password that follows every rule" do
      expect(described_class.violations("Lago-Passw0rd")).to eq([])
      expect(described_class.violations("Été-2026!")).to eq([])
    end

    it "returns each failed rule" do
      expect(described_class.violations("LAGO-PASSW0RD")).to eq(["password_missing_lowercase"])
      expect(described_class.violations("lago-passw0rd")).to eq(["password_missing_uppercase"])
      expect(described_class.violations("Lago-Password")).to eq(["password_missing_number"])
      expect(described_class.violations("LagoPassw0rd")).to eq(["password_missing_special_character"])
      expect(described_class.violations("Lago Passw0rd")).to eq(["password_missing_special_character"])
    end

    it "returns every failed rule in order" do
      expect(described_class.violations("abc")).to eq(
        %w[password_too_short password_missing_uppercase password_missing_number password_missing_special_character]
      )
    end

    it "needs at least 8 characters" do
      expect(described_class.violations("Lag-0rd")).to eq(["password_too_short"])
      expect(described_class.violations("Lago-0rd")).to eq([])
    end

    it "refuses more than 72 bytes, which bcrypt would ignore" do
      expect(described_class.violations("Aa1-#{"é" * 34}")).to eq([])
      expect(described_class.violations("Aa1-#{"é" * 35}")).to eq(["password_too_long"])
    end
  end
end
