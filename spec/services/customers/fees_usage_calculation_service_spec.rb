# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::FeesUsageCalculationService, type: :service do
  let(:from_datetime) { Time.parse("2025-07-01T00:00:00Z") }
  let(:to_datetime) { Time.parse("2025-07-31T23:59:59Z") }
  let(:charges_duration_in_days) { nil }
  let(:amount_cents) { nil }
  let(:recurring) { false }
  let(:fees) do
    [
      instance_double(
        Fee,
        amount_cents: 1000,
        units: "10.5",
        charge: instance_double(
          Charge,
          billable_metric: instance_double(BillableMetric, recurring?: recurring)
        )
      ),
      instance_double(
        Fee,
        amount_cents: 500,
        units: "5.0",
        charge: instance_double(
          Charge,
          billable_metric: instance_double(BillableMetric, recurring?: recurring)
        )
      )
    ]
  end

  let(:service) do
    described_class.new(
      fees:,
      from_datetime:,
      to_datetime:,
      charges_duration_in_days:,
      amount_cents:
    )
  end

  describe "#current_amount_cents" do
    it "returns the sum of the amount_cents from all fees" do
      expect(service.current_amount_cents).to eq(1500)
    end
  end

  describe "#current_units" do
    it "returns the sum of the units from all fees as a BigDecimal" do
      expect(service.current_units).to eq(BigDecimal("15.5"))
    end
  end

  describe "#projected_amount_cents" do
    context "when the charge is recurring" do
      let(:recurring) { true }

      it "returns the current amount" do
        expect(service.projected_amount_cents).to eq(1500)
      end
    end

    context "when the charge is not recurring" do
      let(:recurring) { false }

      context "when at the middle of the billing period" do
        it "returns the projected amount based on a 0.5 time ratio" do
          # Period is 31 days (July). Middle is on the 16th day.
          # Ratio = 16 / 31 = ~0.516
          # Projection = 1500 / 0.516 = ~2906
          travel_to(Time.parse("2025-07-16T12:00:00Z")) do
            expect(service.projected_amount_cents).to eq(2906)
          end
        end
      end

      context "when at the end of the billing period" do
        it "returns the current amount" do
          travel_to(Time.parse("2025-08-01T00:00:00Z")) do
            expect(service.projected_amount_cents).to eq(1500)
          end
        end
      end

      context "when it is before the billing period starts" do
        it "returns 0" do
          travel_to(Time.parse("2025-06-30T00:00:00Z")) do
            expect(service.projected_amount_cents).to eq(0)
          end
        end
      end

      context "when an amount_cents override is provided" do
        let(:amount_cents) { 5000 }

        it "uses the override amount for the projection" do
          travel_to(Time.parse("2025-07-16T12:00:00Z")) do
            # Projection = 5000 / 0.516 = ~9688
            expect(service.projected_amount_cents).to eq(9688)
          end
        end
      end

      context "with a custom charges_duration_in_days" do
        let(:charges_duration_in_days) { 30 } # Use a 30-day month for calculation

        it "calculates projection based on the custom duration" do
          travel_to(Time.parse("2025-07-16T12:00:00Z")) do
            # Ratio = 16 / 30 = ~0.533
            # Projection = 1500 / 0.533 = ~2813
            expect(service.projected_amount_cents).to eq(2813)
          end
        end
      end
    end
  end

  describe "#projected_units" do
    context "when the charge is recurring" do
      let(:recurring) { true }

      it "returns the current units" do
        expect(service.projected_units).to eq(BigDecimal("15.5"))
      end
    end

    context "when the charge is not recurring" do
      let(:recurring) { false }

      it "returns the projected units based on the time ratio" do
        travel_to(Time.parse("2025-07-16T12:00:00Z")) do
          # Projection = 15.5 / 0.516 = ~30.03
          expect(service.projected_units).to eq(BigDecimal("30.03"))
        end
      end

      it "returns 0 before the period starts" do
        travel_to(Time.parse("2025-06-30T00:00:00Z")) do
          expect(service.projected_units).to eq(BigDecimal("0"))
        end
      end
    end
  end
end
