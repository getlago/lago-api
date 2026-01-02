# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::BuildPayInAdvanceFixedChargeService do
  subject(:result) do
    described_class.call(subscription:, fixed_charge:, fixed_charge_event:, timestamp:)
  end

  around { |test| lago_premium!(&test) }

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

    it "does not create a fee" do
      expect(result).to be_success
      expect(result.fee).not_to be_present
    end

    context "when organization as zero_amount_fees premium integration" do
      before do
        organization.update!(premium_integrations: ["zero_amount_fees"])
      end

      it "creates a zero-amount fee (no refund)" do
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(0)
        expect(result.fee.amount_cents).to eq(0)
      end
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

    it "returns no fee" do
      expect(result).to be_success
      expect(result.fee).not_to be_present
    end

    context "when organization as zero_amount_fees premium integration" do
      before do
        organization.update!(premium_integrations: ["zero_amount_fees"])
      end

      it "creates a zero-amount fee (no refund)" do
        expect(result).to be_success
        expect(result.fee).to be_present
        expect(result.fee.units).to eq(0)
        expect(result.fee.amount_cents).to eq(0)
      end
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
end
