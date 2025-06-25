# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::FixedChargeService, type: :service do
  subject(:fixed_charge_service) do
    described_class.call(
      invoice:,
      fixed_charge:,
      subscription:,
      boundaries: boundaries.to_h
    )
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: "monthly") }
  let(:add_on) { create(:add_on, organization:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:invoice) { create(:invoice, organization:, customer:) }
  let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, properties: {amount: "31.00"}) }

  let(:boundaries) do
    {
      charges_from_datetime: subscription.started_at,
      charges_to_datetime: subscription.started_at.end_of_month
    }
  end

  context "with standard charge model" do
    context "when fixed charge is not prorated" do
      let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, prorated: false, properties: {amount: "31.00"}) }

      before do
        # Create a fixed charge event
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: "fixed_charge",
          properties: {units: 2},
          metadata: {fixed_charge_id: fixed_charge.id},
          timestamp: subscription.started_at
        )

        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: "fixed_charge",
          properties: {units: 3},
          metadata: {fixed_charge_id: fixed_charge.id},
          timestamp: subscription.started_at + 1.day
        )
      end

      it "creates fee with full amount" do
        result = fixed_charge_service

        expect(result).to be_success
        expect(result.fees.count).to eq(1)

        fee = result.fees.first
        expect(fee).to have_attributes(
          fixed_charge:,
          invoice:,
          subscription:,
          fee_type: "fixed_charge",
          units: 5, # 2 + 3 from events
          amount_cents: 15500, # 5 * 31 * 100
          amount_currency: subscription.plan.amount_currency,
          organization_id: organization.id,
          billing_entity_id: billing_entity.id,
          events_count: 2
        )
      end
    end

    context "when fixed charge is prorated" do
      let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, prorated: true, properties: {amount: "31.00"}) }

      before do
        create(
          :event,
          organization:,
          external_subscription_id: subscription.external_id,
          code: add_on.code,
          source: "fixed_charge",
          properties: {units: 1},
          metadata: {fixed_charge_id: fixed_charge.id},
          timestamp: subscription.started_at + 1.day
        )
      end

      context "with subscription starting May 10 and renewing June 1 (22 days)" do
        let(:subscription) do
          create(:subscription, customer:, plan:, started_at: Date.new(2024, 5, 10))
        end

        let(:boundaries) do
          {
            charges_from_datetime: subscription.started_at,
            charges_to_datetime: Date.new(2024, 6, 1)
          }
        end

        it "creates fee with prorated amount" do
          result = fixed_charge_service

          expect(result).to be_success
          expect(result.fees.count).to eq(1)

          fee = result.fees.first

          # Expected calculation: aggregated units * full amount
          # 22 days / 31 days = 0.71 proration
          # 0.71 * 31.00 = 22.01
          expect(fee.amount_cents).to eq(2201) # $22.01 * 100 cents
          expect(fee.units).to be_within(0.01).of(0.71) # Prorated units
        end
      end

      context "with subscription starting May 1 and renewing June 1 (31 days)" do
        let(:subscription) do
          create(:subscription, customer:, plan:, started_at: Date.new(2024, 5, 1))
        end

        let(:boundaries) do
          {
            charges_from_datetime: subscription.started_at,
            charges_to_datetime: Date.new(2024, 6, 1)
          }
        end

        it "creates fee with full amount" do
          result = fixed_charge_service

          expect(result).to be_success
          expect(result.fees.count).to eq(1)

          fee = result.fees.first

          # Expected calculation: aggregated units * full amount
          # 31 days / 31 days = 1.0 proration
          # 1.0 * 31.00 = 31.00
          expect(fee.amount_cents).to eq(3100) # $31.00 * 100 cents
          expect(fee.units).to eq(1.0) # Full units
        end
      end
    end

    context "when no events exist" do
      before do
        Event.destroy_all
      end

      it "returns success without creating fees" do
        result = fixed_charge_service

        expect(result).to be_success
        expect(result.fees).to be_empty
      end
    end

    context "when fee already exists" do
      before do
        create(
          :fee,
          fixed_charge:,
          subscription:,
          invoice:,
          properties: boundaries.to_h
        )
      end

      it "returns existing fees without creating new ones" do
        result = fixed_charge_service

        expect(result).to be_success
        expect(result.fees.count).to eq(1)
        expect(result.fees.first.fixed_charge).to eq(fixed_charge)
      end
    end
  end
end
