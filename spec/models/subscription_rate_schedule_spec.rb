# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateSchedule do
  subject { create(:subscription_rate_schedule) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(pending: "pending", active: "active", terminated: "terminated")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription)
      expect(subject).to belong_to(:product_item)
      expect(subject).to belong_to(:rate_schedule)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_numericality_of(:intervals_billed)
        .is_greater_than_or_equal_to(0)
    end
  end

  describe "#update_next_billing_date!" do
    subject(:srs) do
      create(:subscription_rate_schedule,
        rate_schedule:,
        started_at: Date.new(2026, 1, 1),
        intervals_billed: 0)
    end

    let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "month", billing_interval_count: 1) }

    it "increments intervals_billed and sets next_billing_date" do
      srs.update_next_billing_date!

      expect(srs.intervals_billed).to eq(1)
      expect(srs.next_billing_date).to eq(Date.new(2026, 2, 1))
    end

    it "computes correctly after multiple billings" do
      3.times { srs.update_next_billing_date! }

      expect(srs.intervals_billed).to eq(3)
      expect(srs.next_billing_date).to eq(Date.new(2026, 4, 1))
    end

    context "when billing_interval_unit is week" do
      let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "week", billing_interval_count: 1) }

      it "advances by weeks" do
        srs.update_next_billing_date!

        expect(srs.next_billing_date).to eq(Date.new(2026, 1, 8))
      end
    end

    context "when billing_interval_unit is day" do
      let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "day", billing_interval_count: 1) }

      it "advances by days" do
        srs.update_next_billing_date!

        expect(srs.next_billing_date).to eq(Date.new(2026, 1, 2))
      end
    end

    context "when billing_interval_unit is year" do
      let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "year", billing_interval_count: 1) }

      it "advances by years" do
        srs.update_next_billing_date!

        expect(srs.next_billing_date).to eq(Date.new(2027, 1, 1))
      end
    end

    context "when billing_interval_count is greater than 1" do
      let(:rate_schedule) { create(:rate_schedule, billing_interval_unit: "month", billing_interval_count: 3) }

      it "advances by multiple intervals" do
        srs.update_next_billing_date!

        expect(srs.intervals_billed).to eq(1)
        expect(srs.next_billing_date).to eq(Date.new(2026, 4, 1))
      end
    end

    context "when started_at is nil" do
      subject(:srs) do
        create(:subscription_rate_schedule, rate_schedule:, started_at: nil, intervals_billed: 0)
      end

      it "does nothing" do
        expect { srs.update_next_billing_date! }.not_to change(srs, :next_billing_date)
        expect { srs.update_next_billing_date! }.not_to change(srs, :intervals_billed)
      end
    end
  end
end
