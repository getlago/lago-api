# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateSchedule do
  subject { create(:rate_schedule) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:billing_interval_unit)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(day: "day", week: "week", month: "month", year: "year")
      expect(subject).to define_enum_for(:charge_model)
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
      expect(subject).to define_enum_for(:regroup_paid_fees)
        .backed_by_column_of_type(:enum)
        .with_values(invoice: "invoice")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:plan_product_item)
      expect(subject).to belong_to(:product_item)
      expect(subject).to belong_to(:product_item_filter).optional
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_numericality_of(:billing_interval_count)
        .is_greater_than_or_equal_to(1)
      expect(subject).to validate_presence_of(:position)
    end

    describe "amount_currency inclusion" do
      it "rejects invalid currency" do
        rate_schedule = build(:rate_schedule, amount_currency: "INVALID")
        expect(rate_schedule).not_to be_valid
        expect(rate_schedule.errors[:amount_currency]).to be_present
      end
    end
  end
end
