# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCardRate do
  subject(:rate_card_rate) { build(:rate_card_rate) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(rate_card_rate).to define_enum_for(:rate_model)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(
          standard: "standard",
          graduated: "graduated",
          package: "package",
          percentage: "percentage",
          volume: "volume",
          graduated_percentage: "graduated_percentage",
          custom: "custom",
          dynamic: "dynamic"
        )

      expect(rate_card_rate).to define_enum_for(:billing_interval_unit)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(day: "day", week: "week", month: "month", year: "year")
    end
  end

  describe "associations" do
    it do
      expect(rate_card_rate).to belong_to(:organization)
      expect(rate_card_rate).to belong_to(:rate_card)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:effective_datetime) }

    it { is_expected.to validate_numericality_of(:min_amount_cents).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:billing_interval_count).is_greater_than_or_equal_to(1) }

    describe "append-only effective_datetime" do
      let(:rate_card) { create(:rate_card) }

      before { create(:rate_card_rate, rate_card:, effective_datetime: Time.zone.parse("2026-01-01")) }

      it "allows a rate strictly after the latest existing rate" do
        rate = build(:rate_card_rate, rate_card:, effective_datetime: Time.zone.parse("2026-02-01"))
        expect(rate).to be_valid
      end

      it "rejects a rate on or before the latest existing rate" do
        rate = build(:rate_card_rate, rate_card:, effective_datetime: Time.zone.parse("2026-01-01"))
        rate.valid?
        expect(rate.errors.added?(:effective_datetime, :must_be_after_latest_rate)).to be(true)
      end
    end

    describe "applied_pricing_unit_conversion_rate" do
      it "is required when the card carries an applied_pricing_unit_code" do
        rate_card = create(:rate_card, applied_pricing_unit_code: "credits")
        rate = build(:rate_card_rate, rate_card:, applied_pricing_unit_conversion_rate: nil)
        rate.valid?
        expect(rate.errors.added?(:applied_pricing_unit_conversion_rate, :blank)).to be(true)
      end

      it "is not required when the card has no applied_pricing_unit_code" do
        rate = build(:rate_card_rate, applied_pricing_unit_conversion_rate: nil)
        rate.valid?
        expect(rate.errors.added?(:applied_pricing_unit_conversion_rate, :blank)).to be(false)
      end
    end
  end
end
