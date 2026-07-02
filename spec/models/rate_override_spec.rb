# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateOverride do
  subject(:rate_override) { build(:rate_override) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(rate_override).to define_enum_for(:rate_model)
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

      expect(rate_override).to define_enum_for(:billing_interval_unit)
        .backed_by_column_of_type(:enum)
        .validating(allowing_nil: true)
        .with_values(day: "day", week: "week", month: "month", year: "year")
    end
  end

  describe "associations" do
    it do
      expect(rate_override).to belong_to(:organization)
      expect(rate_override).to have_many(:rate_phases)
    end
  end

  describe "validations" do
    it { is_expected.to validate_numericality_of(:min_amount_cents).is_greater_than_or_equal_to(0) }

    describe "billing_interval_count" do
      it "allows nil (inherits the card's active rate)" do
        expect(build(:rate_override, billing_interval_count: nil)).to be_valid
      end

      it "rejects a value below 1" do
        override = build(:rate_override, billing_interval_count: 0)
        override.valid?
        expect(override.errors.where(:billing_interval_count)).to be_present
      end
    end

    describe "rate_properties" do
      it "rejects properties that are invalid for the rate model" do
        override = build(:rate_override, rate_model: "graduated", rate_properties: {})
        override.valid?
        expect(override.errors.where(:rate_properties)).to be_present
      end
    end
  end
end
