# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharges::ProratedAggregationService, type: :service do
  subject(:aggregation_service) do
    described_class.call(
      fixed_charge:,
      subscription:,
      boundaries: boundaries.to_h
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: "monthly") }
  let(:add_on) { create(:add_on, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:, started_at: Date.new(2025, 5, 1)) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, prorated: true) }

  let(:boundaries) do
    {
      charges_from_datetime: subscription.started_at,
      charges_to_datetime: subscription.started_at.end_of_month
    }
  end

  before do
    # Create a fixed charge event
    create(
      :event,
      organization:,
      external_subscription_id: subscription.external_id,
      code: add_on.code,
      source: "fixed_charge",
      properties: {units: 1},
      metadata: {fixed_charge_id: fixed_charge.id},
      timestamp: subscription.started_at
    )
  end

  context "when fixed charge is prorated" do
    it "calculates prorated aggregation correctly" do
      result = aggregation_service

      expect(result).to be_success
      expect(result.full_units_number).to eq(1)
      expect(result.count).to eq(1)
      expect(result.full_period_days).to eq(31) # Default monthly plan

      # For a monthly plan, if subscription starts mid-month, the proration should be less than 1
      subscription_days = subscription.date_diff_with_timezone(
        boundaries[:charges_from_datetime],
        boundaries[:charges_to_datetime]
      )
      expected_proration = subscription_days.fdiv(result.full_period_days)

      expect(result.aggregation).to eq((1 * expected_proration).ceil(5))
    end
  end

  context "when fixed charge is not prorated" do
    let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, prorated: false) }

    it "returns full units without proration" do
      result = aggregation_service

      expect(result).to be_success
      expect(result.aggregation).to eq(1)
      expect(result.full_units_number).to eq(1)
      expect(result.count).to eq(1)
      expect(result.full_period_days).to eq(31) # Default monthly plan
    end
  end

  context "when subscription starts on the first day of the month" do
    let(:subscription) do
      create(:subscription, customer:, plan:, started_at: Date.new(2024, 1, 1))
    end

    let(:boundaries) do
      {
        charges_from_datetime: subscription.started_at,
        charges_to_datetime: subscription.started_at.end_of_month
      }
    end

    it "calculates full proration (1.0)" do
      result = aggregation_service

      expect(result).to be_success
      expect(result.full_period_days).to eq(31) # January 2024 has 31 days
      # Should be close to 1.0 for a full month
      expect(result.aggregation).to be_within(0.01).of(1.0)
    end
  end

  context "when subscription starts mid-month" do
    let(:subscription) do
      create(:subscription, customer:, plan:, started_at: Date.new(2024, 1, 10))
    end

    let(:boundaries) do
      {
        charges_from_datetime: subscription.started_at,
        charges_to_datetime: subscription.started_at.end_of_month
      }
    end

    it "calculates partial proration" do
      result = aggregation_service

      expect(result).to be_success
      expect(result.full_period_days).to eq(31) # January 2024 has 31 days

      # January 10 to January 31 = 22 days
      # 22 / 31 ≈ 0.71
      subscription_days = 22
      expected_proration = subscription_days.fdiv(result.full_period_days)

      expect(result.aggregation).to be_within(0.01).of(expected_proration)
    end
  end

  context "with multiple events" do
    before do
      # Create additional fixed charge events
      create(
        :event,
        organization:,
        external_subscription_id: subscription.external_id,
        code: add_on.code,
        source: "fixed_charge",
        properties: {units: 2},
        metadata: {fixed_charge_id: fixed_charge.id},
        timestamp: subscription.started_at + 1.day
      )
    end

    it "sums all units and applies proration" do
      result = aggregation_service

      expect(result).to be_success
      expect(result.full_units_number).to eq(3) # 1 + 2
      expect(result.count).to eq(2)
      expect(result.full_period_days).to eq(31) # Default monthly plan

      subscription_days = subscription.date_diff_with_timezone(
        boundaries[:charges_from_datetime],
        boundaries[:charges_to_datetime]
      )
      expected_proration = subscription_days.fdiv(result.full_period_days)

      expect(result.aggregation).to eq((3 * expected_proration).ceil(5))
    end
  end

  context "with monthly plan" do
    let(:plan) { create(:plan, organization:, interval: "monthly") }

    context "for January 2024 (31 days)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2024, 1, 15))
      end

      it "returns 31 days in full_period_days" do
        result = aggregation_service
        expect(result.full_period_days).to eq(31)
      end
    end

    context "for February 2024 (29 days - leap year)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2024, 2, 15))
      end

      it "returns 29 days in full_period_days" do
        result = aggregation_service
        expect(result.full_period_days).to eq(29)
      end
    end

    context "for February 2023 (28 days - non-leap year)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2023, 2, 15))
      end

      it "returns 28 days in full_period_days" do
        result = aggregation_service
        expect(result.full_period_days).to eq(28)
      end
    end

    context "for April 2024 (30 days)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2024, 4, 15))
      end

      it "returns 30 days in full_period_days" do
        result = aggregation_service
        expect(result.full_period_days).to eq(30)
      end
    end
  end

  context "with yearly plan" do
    let(:plan) { create(:plan, organization:, interval: "yearly") }

    context "for 2024 (leap year)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2024, 6, 15))
      end

      it "returns 366 days in full_period_days" do
        result = aggregation_service
        expect(result.full_period_days).to eq(366)
      end
    end

    context "for 2023 (non-leap year)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2023, 6, 15))
      end

      it "returns 365 days in full_period_days" do
        result = aggregation_service
        expect(result.full_period_days).to eq(365)
      end
    end
  end

  context "with weekly plan" do
    let(:plan) { create(:plan, organization:, interval: "weekly") }

    it "returns 7 days in full_period_days" do
      result = aggregation_service
      expect(result.full_period_days).to eq(7)
    end
  end

  context "with quarterly plan" do
    let(:plan) { create(:plan, organization:, interval: "quarterly") }

    context "for Q1 2024 (Jan-Mar)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2024, 1, 15))
      end

      it "returns 91 days in full_period_days (31 + 29 + 31)" do
        result = aggregation_service
        expect(result.full_period_days).to eq(91)
      end
    end

    context "for Q2 2024 (Apr-Jun)" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2024, 4, 15))
      end

      it "returns 91 days in full_period_days (30 + 31 + 30)" do
        result = aggregation_service
        expect(result.full_period_days).to eq(91)
      end
    end

    context "for Q1 2023 (Jan-Mar) - non-leap year" do
      let(:subscription) do
        create(:subscription, customer:, plan:, started_at: Date.new(2023, 1, 15))
      end

      it "returns 90 days in full_period_days (31 + 28 + 31)" do
        result = aggregation_service
        expect(result.full_period_days).to eq(90)
      end
    end
  end
end
