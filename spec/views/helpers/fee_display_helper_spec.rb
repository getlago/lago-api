# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeeDisplayHelper do
  subject(:helper) { described_class }

  describe ".grouped_by_display" do
    let(:charge) { create(:standard_charge, properties:) }
    let(:fee) { create(:fee, charge:, fee_type: "charge", grouped_by:, total_aggregated_units: 10) }
    let(:grouped_by) do
      {
        "key_1" => "mercredi",
        "key_2" => "week_01",
        "key_3" => "2024"
      }
    end
    let(:properties) do
      {
        "amount" => "5",
        "grouped_by" => %w[key_1 key_2 key_3]
      }
    end

    context "when a standard charge fee has grouped_by property" do
      it "formats the grouped_by values with bullet points" do
        expect(helper.grouped_by_display(fee)).to eq(" • mercredi • week_01 • 2024")
      end
    end

    context "when the charge properties are missing the grouped_by property" do
      let(:properties) do
        {
          "amount" => "5"
        }
      end

      it "returns valid response" do
        expect(helper.grouped_by_display(fee)).to eq(" • mercredi • week_01 • 2024")
      end
    end

    context "when some grouped_by values are nil" do
      let(:grouped_by) do
        {
          "key_1" => nil,
          "key_2" => "week_01",
          "key_3" => "2024"
        }
      end

      it "skips nil values and formats only the present values" do
        expect(helper.grouped_by_display(fee)).to eq(" • week_01 • 2024")
      end
    end
  end

  describe ".format_with_precision" do
    subject { helper.format_with_precision(fee, amount) }

    let(:fee) { create(:fee, amount_currency: "USD") }
    let(:amount) { "0.12345678" }

    context "when fee does not have pricing unit usage" do
      it "returns the rounded amount with currency symbol" do
        expect(subject).to eq "$0.123457"
      end
    end

    context "when fee has pricing unit usage" do
      let!(:pricing_unit_usage) { create(:pricing_unit_usage, fee:) }

      it "returns the rounded amount with the pricing unit's short name" do
        expect(subject).to eq "0.123457 #{pricing_unit_usage.short_name}"
      end
    end
  end

  describe ".format_as_currency" do
    subject { helper.format_as_currency(fee, amount) }

    let(:fee) { create(:fee, amount_currency: "USD") }
    let(:amount) { "10.53" }

    context "when fee does not have pricing unit usage" do
      it "returns the amount with the appropriate currency symbol" do
        expect(subject).to eq "$10.53"
      end
    end

    context "when fee has pricing unit usage" do
      let!(:pricing_unit_usage) { create(:pricing_unit_usage, fee:) }

      it "returns the amount with the pricing unit's short name" do
        expect(subject).to eq "10.53 #{pricing_unit_usage.short_name}"
      end
    end
  end

  describe ".format_amount" do
    subject { helper.format_amount(fee) }

    let(:fee) { create(:fee, amount_cents: 1000, amount_currency: "USD") }

    context "when fee does not have pricing unit usage" do
      it "returns fee amount with the appropriate currency symbol" do
        expect(subject).to eq "$10.00"
      end
    end

    context "when fee has pricing unit usage" do
      let!(:pricing_unit_usage) { create(:pricing_unit_usage, fee:, amount_cents: 505) }

      it "returns fee's pricing unit usage amount and with the unit's short name" do
        expect(subject).to eq "5.05 #{pricing_unit_usage.short_name}"
      end
    end
  end
end
