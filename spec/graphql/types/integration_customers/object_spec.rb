# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::IntegrationCustomers::Object do
  it "includes the QuickBooks customer type" do
    expect(described_class.possible_types).to include(Types::IntegrationCustomers::Quickbooks)
  end

  describe ".resolve_type" do
    it "resolves a QuickBooks customer" do
      expect(described_class.resolve_type(build(:quickbooks_customer), {})).to eq(Types::IntegrationCustomers::Quickbooks)
    end

    it "still resolves a Xero customer" do
      expect(described_class.resolve_type(build(:xero_customer), {})).to eq(Types::IntegrationCustomers::Xero)
    end

    it "raises on an unexpected class" do
      expect { described_class.resolve_type(build(:customer), {}) }
        .to raise_error(RuntimeError, /Unexpected integration customer type/)
    end
  end
end
