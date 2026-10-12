# frozen_string_literal: true

require "rails_helper"

RSpec.describe QuoteVersions::DealExpiration do
  let_it_be(:organization) { create_default(:organization) }

  before_all do
    create_default(:customer)
  end

  let(:quote) { create(:quote, organization:) }
  let(:billing_items) { {"plans" => [{"payload" => {"endDate" => "2026-06-01T00:00:00Z"}}]} }
  let(:quote_version) { build(:quote_version, quote:, organization:, billing_items:) }

  describe ".earliest" do
    it "returns the plan ending date" do
      expect(described_class.earliest(quote_version)).to eq(Date.new(2026, 6, 1))
    end

    context "when the deal carries no dates" do
      let(:billing_items) { {} }

      it "returns nil" do
        expect(described_class.earliest(quote_version)).to be_nil
      end
    end

    context "when the plans end at different dates" do
      let(:billing_items) do
        {
          "plans" => [
            {"payload" => {"endDate" => "2027-03-15T00:00:00Z"}},
            {"payload" => {"endDate" => "2026-03-15T00:00:00Z"}}
          ]
        }
      end

      it "returns the earliest plan ending date" do
        expect(described_class.earliest(quote_version)).to eq(Date.new(2026, 3, 15))
      end
    end

    context "when a wallet expires before the plans" do
      let(:billing_items) do
        {
          "plans" => [{"payload" => {"endDate" => "2026-06-01T00:00:00Z"}}],
          "walletCredits" => [{"payload" => {"expirationAt" => "2026-02-01T00:00:00Z"}}]
        }
      end

      it "returns the wallet expiration" do
        expect(described_class.earliest(quote_version)).to eq(Date.new(2026, 2, 1))
      end
    end

    context "when a recurring rule expires before everything else" do
      let(:billing_items) do
        {
          "plans" => [{"payload" => {"endDate" => "2026-06-01T00:00:00Z"}}],
          "walletCredits" => [
            {
              "payload" => {
                "expirationAt" => "2026-02-01T00:00:00Z",
                "recurringTransactionRules" => [
                  {"expirationAt" => "2026-05-01T00:00:00Z"},
                  {"expirationAt" => "2026-01-10T00:00:00Z"}
                ]
              }
            }
          ]
        }
      end

      it "returns the earliest rule expiration" do
        expect(described_class.earliest(quote_version)).to eq(Date.new(2026, 1, 10))
      end
    end

    # The only dates a one_off deal carries are fee service periods, legitimately in the past.
    context "when the deal is one_off" do
      let(:quote_version) { build(:quote_version, :with_one_off_billing_items, quote:, organization:) }

      it "returns nil" do
        expect(described_class.earliest(quote_version)).to be_nil
      end
    end

    context "when the billing items are nil" do
      let(:billing_items) { nil }

      it "returns nil" do
        expect(described_class.earliest(quote_version)).to be_nil
      end
    end

    context "when the billing items are not an object" do
      let(:billing_items) { ["plans"] }

      it "returns nil" do
        expect(described_class.earliest(quote_version)).to be_nil
      end
    end

    context "when a quoted date is not a date" do
      let(:billing_items) { {"plans" => [{"payload" => {"endDate" => "whenever"}}]} }

      it "ignores it" do
        expect(described_class.earliest(quote_version)).to be_nil
      end
    end

    context "when a plan carries no payload" do
      let(:billing_items) do
        {"plans" => [{"id" => "plan-id"}, {"payload" => {"endDate" => "2026-06-01T00:00:00Z"}}]}
      end

      it "ignores it" do
        expect(described_class.earliest(quote_version)).to eq(Date.new(2026, 6, 1))
      end
    end
  end

  describe ".covers?" do
    it "covers a date before the expiration" do
      expect(described_class.covers?(quote_version, "2026-05-31T23:00:00Z")).to eq(true)
    end

    # The execution flow requires the ending date to be strictly after the day it runs.
    it "does not cover the expiration day itself" do
      expect(described_class.covers?(quote_version, "2026-06-01T00:00:00Z")).to eq(false)
    end

    it "does not cover a date after the expiration" do
      expect(described_class.covers?(quote_version, "2026-06-02T00:00:00Z")).to eq(false)
    end

    it "covers a blank value" do
      expect(described_class.covers?(quote_version, nil)).to eq(true)
    end

    it "covers a value no date can be read from" do
      expect(described_class.covers?(quote_version, "whenever")).to eq(true)
    end

    it "covers a datetime object" do
      expect(described_class.covers?(quote_version, Time.zone.parse("2026-05-01T00:00:00Z"))).to eq(true)
    end

    context "when the deal carries no dates" do
      let(:billing_items) { {} }

      it "covers any date" do
        expect(described_class.covers?(quote_version, "2099-01-01T00:00:00Z")).to eq(true)
      end
    end
  end
end
