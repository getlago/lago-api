# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::BuildPayInAdvanceFixedChargeService, :premium do
  subject(:result) do
    described_class.call(subscription:, fixed_charge:, fixed_charge_event:, timestamp:)
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: true) }
  let(:add_on) { create(:add_on, organization:) }
  let(:subscription) do
    create(
      :subscription,
      organization:,
      customer:,
      plan:,
      status: :active,
      started_at: Time.zone.parse("2024-03-01")
    )
  end

  let(:fixed_charge) do
    create(
      :fixed_charge,
      plan:,
      add_on:,
      units: 10,
      properties: {amount: "10"},
      prorated: false,
      pay_in_advance: true
    )
  end

  let(:timestamp) { Time.zone.parse("2024-03-15").to_i }

  context "when there are no existing fees (fixed charge added)" do
    let(:fixed_charge_event) do
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 10,
        timestamp: Time.zone.at(timestamp)
      )
    end

    it "creates a fee for all units" do
      expect(result).to be_success
      expect(result.fee).to be_present
      expect(result.fee.units).to eq(10)
      expect(result.fee.amount_cents).to eq(10_000) # 10 units * $10 = $100
    end
  end

  context "when units increase (delta is positive)" do
    let(:boundaries) {
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    }

    let(:existing_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge:,
        fee_type: :fixed_charge,
        units: 10,
        amount_cents: 10_000,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 15,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      existing_fee
    end

    it "creates a fee for only the delta units" do
      expect(result).to be_success
      expect(result.fee).to be_present
      expect(result.fee.units).to eq(5) # 15 - 10 = 5 delta units
      expect(result.fee.amount_cents).to eq(5_000) # 5 units * $10 = $50
    end
  end

  context "when units decrease (delta is negative)" do
    let(:boundaries) do
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    end

    let(:existing_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge:,
        fee_type: :fixed_charge,
        units: 10,
        amount_cents: 10_000,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 5,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      existing_fee
    end

    it "creates a zero-amount fee (no refund)" do
      expect(result).to be_success
      expect(result.fee).to be_present
      expect(result.fee.units).to eq(0)
      expect(result.fee.amount_cents).to eq(0)
    end
  end

  context "when units stay the same (delta is zero)" do
    let(:boundaries) do
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    end

    let(:existing_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge:,
        fee_type: :fixed_charge,
        units: 10,
        amount_cents: 10_000,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 10,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      existing_fee
    end

    it "creates a zero-amount fee (no refund)" do
      expect(result).to be_success
      expect(result.fee).to be_present
      expect(result.fee.units).to eq(0)
      expect(result.fee.amount_cents).to eq(0)
    end
  end

  context "when there are multiple previous fees in the billing period" do
    let(:boundaries) do
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    end

    let(:first_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge:,
        fee_type: :fixed_charge,
        units: 10,
        amount_cents: 10_000,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:second_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge:,
        fee_type: :fixed_charge,
        units: 5, # Delta from first increase (10 -> 15 = 5)
        amount_cents: 5_000,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      # Increasing from 15 to 20
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 20,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      first_fee
      second_fee
    end

    it "calculates delta from total already paid units" do
      expect(result).to be_success
      expect(result.fee).to be_present
      # Already paid: 10 + 5 = 15, new units: 20, delta: 5
      expect(result.fee.units).to eq(5)
      expect(result.fee.amount_cents).to eq(5_000)
    end
  end

  context "when there are multiple previous fees with decrease in the billing period" do
    let(:boundaries) do
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    end

    let(:first_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge:,
        fee_type: :fixed_charge,
        units: 10,
        amount_cents: 10_000,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:second_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge:,
        fee_type: :fixed_charge,
        units: 0, # Delta from decrease (10 -> 5 = -5)
        amount_cents: 0,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      # Increasing from 5 to 20
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 20,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      first_fee
      second_fee
    end

    it "calculates delta from total already paid units" do
      expect(result).to be_success
      expect(result.fee).to be_present
      # Already paid: 10 + 0 = 10, new units: 20, delta: 10
      expect(result.fee.units).to eq(10)
      expect(result.fee.amount_cents).to eq(10_000)
    end
  end

  context "with prorated fixed charge" do
    let(:fixed_charge) do
      create(
        :fixed_charge,
        plan:,
        add_on:,
        units: 10,
        properties: {amount: "10"},
        prorated: true,
        pay_in_advance: true
      )
    end

    context "when there are no existing fees (fixed charge added mid-period)" do
      let(:timestamp) { Time.zone.parse("2024-03-15").to_i }

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 10,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "creates a prorated fee for all units" do
        # March has 31 days. From March 15 to March 31 is 17 days (31 - 15 + 1)
        # Proration coefficient = 17/31 ≈ 0.548
        # Amount = 10 units * $10 * (17/31) ≈ $54.84
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(10)
        expect(result.fee.amount_cents).to eq(5484) # 10 * 1000 * (17/31) = 5483.87 rounded to 5484
      end
    end

    context "when fixed charge is added on the first day of the billing period" do
      let(:timestamp) { Time.zone.parse("2024-03-01").to_i }

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 10,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "creates a fee with full amount (no proration)" do
        # March 1 to March 31 is 31 days
        # Proration coefficient = 31/31 = 1.0
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(10)
        expect(result.fee.amount_cents).to eq(10_000)
      end
    end

    context "when fixed charge is added on the last day of the billing period" do
      let(:timestamp) { Time.zone.parse("2024-03-31").to_i }

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 10,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "creates a minimally prorated fee" do
        # Only 1 day remaining in period
        # Proration coefficient = 1/31 ≈ 0.032
        # Amount = 10 * $10 * (1/31) ≈ $3.23
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(10)
        expect(result.fee.amount_cents).to eq(323) # 10 * 1000 * (1/31) = 322.58 rounded to 323
      end
    end

    context "when units increase mid-period (delta is positive)" do
      let(:timestamp) { Time.zone.parse("2024-03-20").to_i }
      let(:boundaries) do
        Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
      end

      let(:existing_fee) do
        create(
          :fee,
          organization:,
          subscription:,
          fixed_charge:,
          fee_type: :fixed_charge,
          units: 10,
          amount_cents: 10_000,
          properties: {
            "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
            "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
          }
        )
      end

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 15,
          timestamp: Time.zone.at(timestamp)
        )
      end

      before { existing_fee }

      it "creates a prorated fee for the delta units only" do
        # From March 20 to March 31 is 12 days (31 - 20 + 1)
        # Proration coefficient = 12/31 ≈ 0.387
        # Delta = 15 - 10 = 5 units
        # Amount = 5 * $10 * (12/31) ≈ $19.35
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(5)
        expect(result.fee.amount_cents).to eq(1935) # 5 * 1000 * (12/31) = 1935.48 rounded to 1935
      end
    end

    context "when units decrease (delta is negative)" do
      let(:timestamp) { Time.zone.parse("2024-03-20").to_i }
      let(:boundaries) do
        Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
      end

      let(:existing_fee) do
        create(
          :fee,
          organization:,
          subscription:,
          fixed_charge:,
          fee_type: :fixed_charge,
          units: 10,
          amount_cents: 10_000,
          properties: {
            "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
            "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
          }
        )
      end

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 5,
          timestamp: Time.zone.at(timestamp)
        )
      end

      before { existing_fee }

      it "creates a zero-amount fee (no refund for prorated charges)" do
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(0)
        expect(result.fee.amount_cents).to eq(0)
      end
    end

    context "when there are multiple increases throughout the billing period" do
      let(:timestamp) { Time.zone.parse("2024-03-25").to_i }
      let(:boundaries) do
        Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
      end

      let(:first_fee) do
        create(
          :fee,
          organization:,
          subscription:,
          fixed_charge:,
          fee_type: :fixed_charge,
          units: 5,
          amount_cents: 5_000, # First increase at beginning of period
          properties: {
            "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
            "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
          }
        )
      end

      let(:second_fee) do
        create(
          :fee,
          organization:,
          subscription:,
          fixed_charge:,
          fee_type: :fixed_charge,
          units: 5, # Second increase mid-period (5 -> 10 = delta of 5)
          amount_cents: 2_500, # Already prorated for some portion
          properties: {
            "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
            "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
          }
        )
      end

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 15,
          timestamp: Time.zone.at(timestamp)
        )
      end

      before do
        first_fee
        second_fee
      end

      it "calculates prorated delta from total already paid units" do
        # Already paid: 5 + 5 = 10 units
        # New units: 15, delta: 5
        # From March 25 to March 31 is 7 days (31 - 25 + 1)
        # Proration coefficient = 7/31 ≈ 0.226
        # Amount = 5 * $10 * (7/31) ≈ $11.29
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(5)
        expect(result.fee.amount_cents).to eq(1129) # 5 * 1000 * (7/31) = 1129.03 rounded to 1129
      end
    end

    context "with weekly plan interval" do
      let(:plan) { create(:plan, organization:, interval: "weekly", pay_in_advance: true) }
      let(:subscription) do
        create(
          :subscription,
          organization:,
          customer:,
          plan:,
          status: :active,
          started_at: Time.zone.parse("2024-03-04") # Monday
        )
      end
      let(:timestamp) { Time.zone.parse("2024-03-07").to_i } # Thursday

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 10,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "prorates correctly for weekly billing period" do
        # Week starts March 4 (Mon), ends March 10 (Sun) = 7 days
        # From March 7 (Thu) to March 10 (Sun) is 4 days
        # Proration coefficient = 4/7 ≈ 0.571
        # Amount = 10 * $10 * (4/7) ≈ $57.14
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(10)
        expect(result.fee.amount_cents).to eq(5714) # 10 * 1000 * (4/7) = 5714.29 rounded to 5714
      end
    end

    context "with yearly plan interval" do
      let(:plan) { create(:plan, organization:, interval: "yearly", pay_in_advance: true) }
      let(:subscription) do
        create(
          :subscription,
          organization:,
          customer:,
          plan:,
          status: :active,
          started_at: Time.zone.parse("2024-01-01")
        )
      end
      let(:timestamp) { Time.zone.parse("2024-07-01").to_i } # Mid-year

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 10,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "prorates correctly for yearly billing period" do
        # 2024 is a leap year with 366 days
        # From July 1 to Dec 31 is 184 days
        # Proration coefficient = 184/366 ≈ 0.503
        # Amount = 10 * $10 * (184/366) ≈ $50.27
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(10)
        expect(result.fee.amount_cents).to eq(5027) # 10 * 1000 * (184/366) = 5027.32 rounded to 5027
      end
    end
  end

  context "when units increase and previous fee belongs to parent fixed charge" do
    let(:parent_fixed_charge) do
      create(:fixed_charge, add_on:, units: 5, properties: {amount: "10"}, prorated: false, pay_in_advance: true)
    end

    let(:fixed_charge) do
      create(
        :fixed_charge,
        plan:,
        add_on:,
        units: 15,
        properties: {amount: "10"},
        prorated: false,
        pay_in_advance: true,
        parent: parent_fixed_charge
      )
    end

    let(:boundaries) {
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    }

    let(:existing_fee) do
      create(
        :fee,
        organization:,
        subscription:,
        fixed_charge: parent_fixed_charge,
        fee_type: :fixed_charge,
        units: 5,
        amount_cents: 5_000,
        properties: {
          "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 15,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      existing_fee
    end

    it "creates a fee for only the delta units (15 - 5 = 10)" do
      expect(result).to be_success
      expect(result.fee).to be_present
      expect(result.fee.units).to eq(10) # 15 - 5 = 10 delta units
      expect(result.fee.amount_cents).to eq(10_000) # 10 units * $10 = $100
    end
  end

  context "when organization has the fixed_charge_usage_delta_migration feature flag enabled" do
    let(:organization) { create(:organization, feature_flags: ["fixed_charge_usage_delta_migration"]) }
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:usage_charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        pay_in_advance: true,
        prorated: true,
        deleted_at: Time.current
      )
    end

    let(:boundaries) do
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    end

    let(:usage_fee) do
      create(
        :charge_fee,
        organization:,
        subscription:,
        charge: usage_charge,
        units: 3,
        properties: {
          "charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 4,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      usage_fee
    end

    it "counts the discarded usage charge units as already paid" do
      expect(result).to be_success
      expect(result.fee).to be_present
      expect(result.fee.units).to eq(1) # 4 - 3 = 1 delta unit
      expect(result.fee.amount_cents).to eq(1_000) # 1 unit * $10 = $10
    end

    context "when the fixed charge is prorated" do
      let(:timestamp) { Time.zone.parse("2024-03-20").to_i }
      let(:fixed_charge) do
        create(
          :fixed_charge,
          plan:,
          add_on:,
          units: 10,
          properties: {amount: "10"},
          prorated: true,
          pay_in_advance: true
        )
      end

      it "creates a prorated fee for the delta units only" do
        # From March 20 to March 31 is 12 days (31 - 20 + 1)
        # Delta = 4 - 3 = 1 unit
        # Amount = 1 * $10 * (12/31) ≈ $3.87
        expect(result).to be_success
        expect(result.fee.units).to eq(1)
        expect(result.fee.amount_cents).to eq(387) # 1 * 1000 * (12/31) = 387.09 rounded to 387
      end
    end

    context "when a fixed charge fee also exists for the period" do
      let(:existing_fee) do
        create(
          :fee,
          organization:,
          subscription:,
          fixed_charge:,
          fee_type: :fixed_charge,
          units: 1,
          amount_cents: 1_000,
          properties: {
            "fixed_charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
            "fixed_charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
          }
        )
      end

      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 5,
          timestamp: Time.zone.at(timestamp)
        )
      end

      before do
        existing_fee
      end

      it "sums both fee types as already paid units" do
        expect(result).to be_success
        expect(result.fee.units).to eq(1) # 5 - (3 + 1) = 1 delta unit
        expect(result.fee.amount_cents).to eq(1_000)
      end
    end

    context "when units decrease below the usage charge units" do
      let(:fixed_charge_event) do
        create(
          :fixed_charge_event,
          subscription:,
          fixed_charge:,
          units: 2,
          timestamp: Time.zone.at(timestamp)
        )
      end

      it "creates a zero-amount fee" do
        expect(result).to be_success
        expect(result.fee.units).to eq(0)
        expect(result.fee.amount_cents).to eq(0)
      end
    end

    context "when the usage fee belongs to a previous billing period" do
      let(:usage_fee) do
        create(
          :charge_fee,
          organization:,
          subscription:,
          charge: usage_charge,
          units: 3,
          properties: {
            "charges_from_datetime" => (boundaries[:fixed_charges_from_datetime] - 1.month).iso8601(3),
            "charges_to_datetime" => (boundaries[:fixed_charges_to_datetime] - 1.month).iso8601(3)
          }
        )
      end

      it "does not count the usage charge units" do
        expect(result).to be_success
        expect(result.fee.units).to eq(4)
        expect(result.fee.amount_cents).to eq(4_000)
      end
    end

    context "when the usage charge is not discarded" do
      let(:usage_charge) do
        create(
          :standard_charge,
          plan:,
          billable_metric:,
          pay_in_advance: true,
          prorated: true
        )
      end

      it "does not count the usage charge units" do
        expect(result).to be_success
        expect(result.fee.units).to eq(4)
        expect(result.fee.amount_cents).to eq(4_000)
      end
    end
  end

  context "when organization does not have the fixed_charge_usage_delta_migration feature flag" do
    let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:) }
    let(:usage_charge) do
      create(
        :standard_charge,
        plan:,
        billable_metric:,
        pay_in_advance: true,
        prorated: true,
        deleted_at: Time.current
      )
    end

    let(:boundaries) do
      Subscriptions::DatesService.fixed_charge_pay_in_advance_interval(timestamp, subscription)
    end

    let(:usage_fee) do
      create(
        :charge_fee,
        organization:,
        subscription:,
        charge: usage_charge,
        units: 3,
        properties: {
          "charges_from_datetime" => boundaries[:fixed_charges_from_datetime].iso8601(3),
          "charges_to_datetime" => boundaries[:fixed_charges_to_datetime].iso8601(3)
        }
      )
    end

    let(:fixed_charge_event) do
      create(
        :fixed_charge_event,
        subscription:,
        fixed_charge:,
        units: 4,
        timestamp: Time.zone.at(timestamp)
      )
    end

    before do
      usage_fee
    end

    it "does not count the usage charge units" do
      expect(result).to be_success
      expect(result.fee.units).to eq(4)
      expect(result.fee.amount_cents).to eq(4_000)
    end
  end
end
