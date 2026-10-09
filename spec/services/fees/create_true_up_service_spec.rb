# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::CreateTrueUpService do
  let(:create_service) { described_class.new(fee:, used_amount_cents:, used_precise_amount_cents:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:tax) { create(:tax, organization:, rate: 20) }
  let(:plan) { create(:plan, organization:) }

  let(:charge) { create(:standard_charge, plan:, min_amount_cents: 1000) }
  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:fee) do
    create(
      :charge_fee,
      amount_cents: used_amount_cents,
      precise_amount_cents: used_amount_cents,
      customer:,
      charge:,
      properties: {
        "from_datetime" => DateTime.parse("2023-08-01 00:00:00"),
        "to_datetime" => DateTime.parse("2023-08-31 23:59:59"),
        "charges_from_datetime" => DateTime.parse("2023-08-01 00:00:00"),
        "charges_to_datetime" => DateTime.parse("2023-08-31 23:59:59"),
        "charges_duration" => 31
      }
    )
  end
  let(:used_amount_cents) { 700 }
  let(:used_precise_amount_cents) { 700.0 }

  before { tax }

  describe "#call" do
    subject(:result) { create_service.call }

    context "when fee is nil" do
      let(:fee) { nil }

      it "does not instantiate a true-up fee" do
        expect(result).to be_success
        expect(result.true_up_fee).to be_nil
      end
    end

    context "when min_amount_cents is lower than the fee amount_cents" do
      let(:fee) { create(:charge_fee, amount_cents: 1500, precise_amount_cents: 1500.0) }

      it "does not instantiate a true-up fee" do
        expect(result).to be_success
        expect(result.true_up_fee).to be_nil
      end
    end

    it "instantiates a true-up fee" do
      travel_to(DateTime.new(2023, 4, 1)) do
        expect(result).to be_success

        expect(result.true_up_fee).to be_new_record.and have_attributes(
          subscription: fee.subscription,
          charge: fee.charge,
          amount_currency: fee.currency,
          fee_type: "charge",
          invoiceable: fee.charge,
          properties: fee.properties,
          payment_status: "pending",
          units: 1,
          events_count: 0,
          charge_filter: nil,
          amount_cents: 300,
          precise_amount_cents: 300.0,
          taxes_amount_cents: 2,
          taxes_precise_amount_cents: 2.0000000001,
          unit_amount_cents: 300,
          precise_unit_amount: 3,
          true_up_parent_fee_id: fee.id,
          pricing_unit_usage: nil
        )
      end
    end

    context "with a billing segment" do
      let(:create_service) { described_class.new(fee:, used_amount_cents:, used_precise_amount_cents:, billing_segment:) }
      let(:currency) { "EUR" }
      let(:min_amount_cents) { 1000 }
      let(:proration_ratio) { 1 }
      let(:pricing_unit) { nil }
      let(:conversion_rate) { nil }
      let(:rate_card) { create(:rate_card, organization:, currency:) }
      let(:rate_card_rate) do
        create(:rate_card_rate, organization:, rate_card:, min_amount_cents:, applied_pricing_unit_conversion_rate: conversion_rate)
      end
      let(:contract) { create(:contract, organization:, customer:) }
      let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, rate_card:) }
      let(:billing_segment) do
        create(
          :billing_segment, organization:, customer:, contract_rate_card:, rate_card_rate:,
          contract:, currency:, pricing_unit:, proration_ratio:,
          cycle_started_at: Time.utc(2023, 8, 1), started_at: Time.utc(2023, 8, 1),
          ended_at: BillingSegment.inclusive_end(Time.utc(2023, 9, 1))
        )
      end
      let(:product_filter) { create(:product_filter, organization:, product: rate_card.product) }
      let(:fee) do
        create(
          :fee, organization:, customer:, invoice:, subscription: nil, charge: nil,
          contract:, contract_rate_card:,
          fee_type: :product, invoiceable: rate_card.product, rate_card_rate:, product_filter:,
          amount_currency: currency, amount_cents: used_amount_cents,
          precise_amount_cents: used_precise_amount_cents, properties: {},
          units: 7, total_aggregated_units: 7, events_count: 7
        )
      end

      it "builds an unpersisted product true-up and preserves the parent fee" do
        fee

        expect { result }.not_to change(Fee, :count)
        expect(result).to be_success
        expect(result.true_up_fee).to be_new_record.and have_attributes(
          organization:, invoice:, subscription: nil, charge: nil,
          contract:, contract_rate_card:,
          fee_type: "product", invoiceable: rate_card.product, rate_card_rate:,
          amount_currency: currency, properties: {}, true_up_parent_fee: fee,
          product_filter_id: nil, charge_filter_id: nil,
          units: 1, total_aggregated_units: 1, events_count: 0,
          amount_cents: 300, precise_amount_cents: 300,
          unit_amount_cents: 300, precise_unit_amount: 3, pricing_unit_usage: nil
        )
        expect(fee.reload).to have_attributes(
          product_filter:, amount_cents: 700, precise_amount_cents: 700,
          units: 7, total_aggregated_units: 7, events_count: 7, true_up_parent_fee_id: nil
        )
      end

      context "when fee is nil" do
        let(:fee) { nil }

        it "does not instantiate a true-up fee" do
          expect(result).to be_success
          expect(result.true_up_fee).to be_nil
        end
      end

      context "when usage equals the minimum" do
        let(:used_amount_cents) { 1000 }
        let(:used_precise_amount_cents) { 1000.to_d }

        it "does not instantiate a true-up fee" do
          expect(result).to be_success
          expect(result.true_up_fee).to be_nil
        end
      end

      context "when usage exceeds the minimum" do
        let(:used_amount_cents) { 1500 }
        let(:used_precise_amount_cents) { 1500.to_d }

        it "does not instantiate a true-up fee" do
          expect(result).to be_success
          expect(result.true_up_fee).to be_nil
        end
      end

      context "with no minimum" do
        let(:min_amount_cents) { 0 }
        let(:used_amount_cents) { 0 }
        let(:used_precise_amount_cents) { 0.to_d }

        it "does not instantiate a true-up fee" do
          expect(result).to be_success
          expect(result.true_up_fee).to be_nil
        end
      end

      context "with distinct rounded and precise usage" do
        let(:used_precise_amount_cents) { BigDecimal("700.25") }

        it "preserves precision independently of the rounded amount" do
          expect(result.true_up_fee).to have_attributes(
            amount_cents: 300, precise_amount_cents: BigDecimal("299.75"),
            unit_amount_cents: 300, precise_unit_amount: BigDecimal("2.9975")
          )
        end
      end

      context "with a prorated minimum" do
        let(:proration_ratio) { BigDecimal("0.5") }
        let(:used_amount_cents) { 200 }
        let(:used_precise_amount_cents) { 200.to_d }

        it "uses the segment's stored proration without fee billing boundaries" do
          expect(result.true_up_fee).to have_attributes(
            amount_cents: 300, precise_amount_cents: 300,
            unit_amount_cents: 300, precise_unit_amount: 3
          )
        end

        context "when usage exceeds the prorated minimum" do
          let(:used_amount_cents) { 700 }
          let(:used_precise_amount_cents) { 700.to_d }

          it "does not top up to the full minimum" do
            expect(result).to be_success
            expect(result.true_up_fee).to be_nil
          end
        end
      end

      context "with a zero-decimal currency" do
        let(:currency) { "JPY" }

        it "uses the segment currency's subunit for the unit amount" do
          expect(result.true_up_fee).to have_attributes(
            amount_currency: "JPY", amount_cents: 300, precise_amount_cents: 300,
            unit_amount_cents: 300, precise_unit_amount: 300
          )
        end
      end

      context "with pricing units" do
        let(:pricing_unit) { create(:pricing_unit, organization:) }
        let(:conversion_rate) { BigDecimal("0.25") }

        it "converts the remaining pricing-unit minimum to fiat and builds usage" do
          expect(result).to be_success
          expect(result.true_up_fee).to have_attributes(
            amount_cents: 825, precise_amount_cents: 825,
            unit_amount_cents: 825, precise_unit_amount: BigDecimal("8.25")
          )
          expect(result.true_up_fee.pricing_unit_usage).to be_new_record.and have_attributes(
            organization:, pricing_unit:, short_name: pricing_unit.short_name, conversion_rate: BigDecimal("0.25"),
            amount_cents: 3300, precise_amount_cents: 3300, unit_amount_cents: 3300, precise_unit_amount: 33
          )
        end

        context "with a prorated minimum" do
          let(:proration_ratio) { BigDecimal("0.5") }

          it "prorates the minimum before converting the remaining pricing units" do
            expect(result.true_up_fee).to have_attributes(
              amount_cents: 325, precise_amount_cents: 325,
              unit_amount_cents: 325, precise_unit_amount: BigDecimal("3.25")
            )
            expect(result.true_up_fee.pricing_unit_usage).to have_attributes(
              amount_cents: 1300, precise_amount_cents: 1300, unit_amount_cents: 1300, precise_unit_amount: 13
            )
          end
        end

        context "when pricing-unit usage reaches the minimum" do
          let(:used_amount_cents) { 4000 }
          let(:used_precise_amount_cents) { 4000.to_d }

          it "does not instantiate a true-up fee" do
            expect(result).to be_success
            expect(result.true_up_fee).to be_nil
          end
        end
      end
    end

    context "when fee's charge uses pricing units" do
      before do
        create(
          :applied_pricing_unit,
          organization:,
          conversion_rate: 0.25,
          pricing_unitable: charge
        )
      end

      it "instantiates a true-up fee" do
        travel_to(DateTime.new(2023, 4, 1)) do
          expect(result).to be_success

          expect(result.true_up_fee).to be_new_record.and have_attributes(
            subscription: fee.subscription,
            charge: fee.charge,
            amount_currency: fee.currency,
            fee_type: "charge",
            invoiceable: fee.charge,
            properties: fee.properties,
            payment_status: "pending",
            units: 1,
            events_count: 0,
            charge_filter: nil,
            amount_cents: 75,
            precise_amount_cents: 75.0,
            taxes_amount_cents: 2,
            taxes_precise_amount_cents: 2.0000000001,
            unit_amount_cents: 75,
            precise_unit_amount: 0.75,
            true_up_parent_fee_id: fee.id
          )

          expect(result.true_up_fee.pricing_unit_usage).to be_new_record.and have_attributes(
            amount_cents: 300,
            precise_amount_cents: 300.0,
            unit_amount_cents: 300,
            precise_unit_amount: 3.00
          )
        end
      end
    end

    context "when prorated" do
      let(:used_amount_cents) { 200 }
      let(:used_precise_amount_cents) { 200.0 }

      let(:fee) do
        create(
          :charge_fee,
          amount_cents: used_amount_cents,
          precise_amount_cents: used_amount_cents,
          charge:,
          properties: {
            "from_datetime" => DateTime.parse("2022-08-01 00:00:00"),
            "to_datetime" => DateTime.parse("2022-08-15 23:59:59"),
            "charges_from_datetime" => DateTime.parse("2022-08-01 00:00:00"),
            "charges_to_datetime" => DateTime.parse("2022-08-15 23:59:59"),
            "charges_duration" => 31
          }
        )
      end

      it "instantiates a prorated true-up fee" do
        travel_to(DateTime.new(2023, 4, 1)) do
          expect(result).to be_success

          expect(result.true_up_fee).to have_attributes(
            amount_cents: 284, # (1000 / 31.0 * 15) - 200
            precise_amount_cents: 283.8709677419355
          )
        end
      end
    end

    context "with customer timezone" do
      let(:customer) { create(:customer, organization:, timezone: "Pacific/Fiji") }

      it "instantiates a true-up fee" do
        travel_to(DateTime.new(2023, 9, 1)) do
          expect(result).to be_success

          expect(result.true_up_fee).to have_attributes(
            subscription: fee.subscription,
            charge: fee.charge,
            amount_currency: fee.currency,
            fee_type: "charge",
            invoiceable: fee.charge,
            properties: fee.properties,
            payment_status: "pending",
            units: 1,
            events_count: 0,
            charge_filter: nil,
            amount_cents: 300,
            precise_amount_cents: 300.0,
            unit_amount_cents: 300,
            precise_unit_amount: 3,
            true_up_parent_fee_id: fee.id
          )
        end
      end
    end
  end
end
