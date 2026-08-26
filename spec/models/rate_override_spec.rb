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
      expect(rate_override).to have_one(:rate_phase)
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

  describe "#charge_model" do
    it "exposes the rate model under the calculators' expected name" do
      expect(build(:rate_override).charge_model).to eq("standard")
    end
  end

  describe "#prorated?" do
    it "inherits the structural proration of the card its phase prices" do
      organization = create(:organization)
      product = create(:product, :fixed, organization:)
      rate_card = create(:rate_card, organization:, product:, proration: true)
      plan_rate_card = create(:plan_rate_card, organization:, rate_card:)
      override = create(:rate_override, organization:)
      create(:rate_phase, organization:, plan_rate_card:, position: 1, rate_override: override)

      expect(override.prorated?).to be(true)
    end

    it "defaults to false when not attached to a phase yet" do
      expect(build(:rate_override).prorated?).to be(false)
    end
  end
end
