# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Integrations::Object do
  describe ".resolve_type" do
    it "resolves a QuickBooks integration" do
      expect(described_class.resolve_type(build(:quickbooks_integration), {})).to eq(Types::Integrations::Quickbooks)
    end

    it "still resolves a Xero integration" do
      expect(described_class.resolve_type(build(:xero_integration), {})).to eq(Types::Integrations::Xero)
    end
  end
end
