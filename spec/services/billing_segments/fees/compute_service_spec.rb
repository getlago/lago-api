# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::Fees::ComputeService do
  describe ".call" do
    subject(:result) { described_class.call(billing_segment:) }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:, currency: "USD") }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:rate_card) { create(:rate_card, organization:, product: fixed_product, currency: "USD") }
    let(:fixed_product) { create(:product, :fixed, organization:) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, units:, effective_date: Date.new(2026, 8, 1))
    end
    let(:rate_card_rate) do
      create(:rate_card_rate, organization:, rate_card:, rate_model:, rate_properties:, min_amount_cents:)
    end
    let(:billing_segment) do
      create(
        :billing_segment,
        organization:,
        contract:,
        customer:,
        contract_rate_card:,
        rate_card_rate:,
        rate_properties:,
        proration_ratio:,
        cycle_started_at: Time.utc(2026, 8, 1),
        started_at: Time.utc(2026, 8, 1),
        ended_at: Time.utc(2026, 8, 31).end_of_day
      )
    end
    let(:units) { 15 }
    let(:min_amount_cents) { 0 }
    let(:proration_ratio) { 1 }

    context "with a standard rate model" do
      let(:rate_model) { "standard" }
      let(:rate_properties) { {"amount" => "30"} }

      it "prices the fee" do
        expect(result).to be_success
        expect(result.fee.amount_cents).to eq(45_000)
        expect(result.fee.unit_amount_cents).to eq(3_000)
        expect(result.fee.precise_unit_amount).to eq(30)
        expect(result.fee.invoiceable).to eq(fixed_product)
        expect(result.fee.amount_currency).to eq("USD")
        expect(result.fee.properties).to eq(
          "from_datetime" => billing_segment.started_at.iso8601(3),
          "to_datetime" => billing_segment.ended_at.iso8601(3),
          "charges_from_datetime" => billing_segment.started_at.iso8601(3),
          "charges_to_datetime" => billing_segment.ended_at.iso8601(3),
          "charges_duration" => billing_segment.duration_in_days,
          "timestamp" => billing_segment.billing_at.iso8601(3),
          "fixed_charges_from_datetime" => nil,
          "fixed_charges_to_datetime" => nil,
          "fixed_charges_duration" => nil,
          "billing_segment_id" => billing_segment.id
        )
        expect(result.fee.subscription).to be_nil
        expect(result.true_up_fee).to be_nil
      end

      context "with a minimum amount above the fee amount" do
        let(:min_amount_cents) { 100_000 }

        it "returns a linked true-up fee" do
          expect(result).to be_success
          expect(result.true_up_fee).to be_new_record.and have_attributes(
            fee_type: "product",
            invoiceable: result.fee.invoiceable,
            amount_cents: 55_000,
            precise_amount_cents: 55_000,
            units: 1,
            unit_amount_cents: 55_000,
            precise_unit_amount: 550,
            true_up_parent_fee: result.fee,
            pricing_unit_usage: nil
          )
        end
      end

      context "with a partial billing segment" do
        let(:proration_ratio) { 0.5 }
        let(:min_amount_cents) { 100_000 }

        it "uses the stored proration ratio" do
          expect(result).to be_success
          expect(result.fee.amount_cents).to eq(22_500)
          expect(result.true_up_fee.amount_cents).to eq(27_500)
        end
      end

      context "with an elapsed period ratio" do
        let(:customer) { create(:customer, organization:, currency: "USD", timezone: "UTC") }
        let(:proration_ratio) { 0.5 }
        let(:min_amount_cents) { 100_000 }

        before do
          billing_segment
          allow(ChargeModels::Factory).to receive(:new_instance).and_call_original
        end

        {
          "before the segment starts" => [Time.utc(2026, 7, 31, 12), 0.0],
          "on the first day" => [Time.utc(2026, 8, 1, 12), 1.fdiv(31)],
          "during the segment" => [Time.utc(2026, 8, 16, 12), 16.fdiv(31)],
          "on the last day before its end instant" => [Time.utc(2026, 8, 31, 0), 1.0],
          "after the segment ends" => [Time.utc(2026, 9, 1), 1.0]
        }.each do |description, (current_time, expected_ratio)|
          it "passes the elapsed ratio #{description} without changing service proration" do
            travel_to(current_time) do
              expect(result).to be_success
              expect(ChargeModels::Factory).to have_received(:new_instance).with(
                hash_including(period_ratio: expected_ratio, calculate_projected_usage: false)
              )
              expect(result.fee.amount_cents).to eq(22_500)
              expect(result.true_up_fee.amount_cents).to eq(27_500)
            end
          end
        end

        it "measures progress within the segment rather than its parent cycle" do
          billing_segment.update!(started_at: Time.utc(2026, 8, 20), ended_at: Time.utc(2026, 8, 29).end_of_day)

          travel_to(Time.utc(2026, 8, 21, 12)) do
            expect(result).to be_success
            expect(ChargeModels::Factory).to have_received(:new_instance).with(
              hash_including(period_ratio: 2.fdiv(10))
            )
          end
        end

        context "with a customer timezone different from UTC" do
          let(:customer) { create(:customer, organization:, currency: "USD", timezone: "America/New_York") }

          it "uses the customer's date when UTC has already reached the last day" do
            billing_segment.update!(
              cycle_started_at: Time.utc(2026, 8, 1, 4), started_at: Time.utc(2026, 8, 1, 4),
              ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1, 4))
            )

            travel_to(Time.utc(2026, 8, 31, 2)) do
              expect(result).to be_success
              expect(ChargeModels::Factory).to have_received(:new_instance).with(
                hash_including(period_ratio: 30.fdiv(31))
              )
            end
          end
        end
      end

      context "with a fixed product and pricing unit" do
        let(:pricing_unit) { create(:pricing_unit, organization:, code: "credits", short_name: "cr") }
        let(:rate_card) do
          create(:rate_card, organization:, product: fixed_product, currency: "USD", applied_pricing_unit_code: pricing_unit.code)
        end
        let(:rate_properties) { {"amount" => "10"} }
        let(:rate_card_rate) do
          create(
            :rate_card_rate,
            organization:,
            rate_card:,
            rate_model:,
            rate_properties:,
            applied_pricing_unit_conversion_rate: 0.5,
            min_amount_cents:
          )
        end
        let(:units) { 5 }

        before { billing_segment.update!(pricing_unit:) }

        it "converts the pricing unit amount to fiat currency" do
          expect(result).to be_success
          expect(result.fee.amount_cents).to eq(2_500)
          expect(result.fee.unit_amount_cents).to eq(500)
          expect(result.fee.precise_unit_amount).to eq(5)
          expect(result.fee.pricing_unit_usage).to have_attributes(
            pricing_unit:,
            short_name: "cr",
            amount_cents: 5_000,
            precise_amount_cents: 5_000,
            unit_amount_cents: 1_000,
            precise_unit_amount: 10,
            conversion_rate: 0.5
          )
        end

        context "with a minimum amount above the converted fee amount" do
          let(:min_amount_cents) { 10_000 }

          it "returns a linked true-up fee with pricing unit usage" do
            expect(result).to be_success
            expect(result.true_up_fee).to be_new_record.and have_attributes(
              amount_cents: 7_500,
              precise_amount_cents: 7_500,
              units: 1,
              unit_amount_cents: 7_500,
              precise_unit_amount: 75,
              true_up_parent_fee: result.fee
            )
            expect(result.true_up_fee.pricing_unit_usage).to be_new_record.and have_attributes(
              pricing_unit:,
              amount_cents: 15_000,
              precise_amount_cents: 15_000,
              unit_amount_cents: 15_000,
              precise_unit_amount: 150,
              conversion_rate: 0.5
            )
          end
        end
      end
    end

    context "with a graduated rate model" do
      let(:rate_model) { "graduated" }
      let(:rate_properties) do
        {"graduated_ranges" => [
          {"from_value" => 0, "to_value" => 10, "per_unit_amount" => "10", "flat_amount" => "2"},
          {"from_value" => 11, "to_value" => nil, "per_unit_amount" => "5", "flat_amount" => "3"}
        ]}
      end

      it "prices the fee" do
        expect(result).to be_success
        expect(result.fee.amount_cents).to eq(13_000)
        expect(result.fee.unit_amount_cents).to eq(866)
        expect(result.fee.precise_unit_amount).to be_within(0.000000000000001).of(BigDecimal(130) / 15)
        expect(result.fee.amount_details["graduated_ranges"].count).to eq(2)
      end

      context "with a fixed product" do
        let(:rate_card) { create(:rate_card, organization:, product: fixed_product, currency: "USD") }
        let(:units) { 5 }
        let(:rate_properties) do
          {"graduated_ranges" => [
            {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
            {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
          ]}
        end

        it "prices the fixed product fee from graduated ranges" do
          expect(result).to be_success
          expect(result.fee.amount_cents).to eq(4_200)
          expect(result.fee.unit_amount_cents).to eq(840)
          expect(result.fee.precise_unit_amount).to eq(8.4)
          expect(result.fee.amount_details["graduated_ranges"]).not_to eq([])
        end
      end
    end

    context "with a volume rate model" do
      let(:rate_model) { "volume" }
      let(:rate_properties) do
        {"volume_ranges" => [
          {"from_value" => 0, "to_value" => 10, "per_unit_amount" => "10", "flat_amount" => "2"},
          {"from_value" => 11, "to_value" => nil, "per_unit_amount" => "5", "flat_amount" => "3"}
        ]}
      end

      it "prices the fee" do
        expect(result).to be_success
        expect(result.fee.amount_cents).to eq(7_800)
        expect(result.fee.unit_amount_cents).to eq(520)
        expect(result.fee.precise_unit_amount).to eq(BigDecimal(78) / 15)
        expect(result.fee.amount_details["per_unit_total_amount"]).to eq("75.0")
      end

      context "with a fixed product" do
        let(:rate_card) { create(:rate_card, organization:, product: fixed_product, currency: "USD") }
        let(:units) { 5 }
        let(:rate_properties) do
          {"volume_ranges" => [
            {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => "0.00"},
            {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => "0.00"}
          ]}
        end

        it "prices the fixed product fee from volume ranges" do
          expect(result).to be_success
          expect(result.fee.amount_cents).to eq(3_000)
          expect(result.fee.unit_amount_cents).to eq(600)
          expect(result.fee.precise_unit_amount).to eq(6)
          expect(result.fee.amount_details["per_unit_total_amount"]).to eq("30.0")
        end
      end
    end

    context "with a package rate model" do
      let(:rate_card) { create(:rate_card, organization:, currency: "USD") }
      let(:rate_model) { "package" }
      let(:rate_properties) { {"amount" => "20", "free_units" => 0, "package_size" => 10} }

      it "prices the fee" do
        expect(result).to be_success
        expect(result.fee.amount_cents).to eq(4_000)
        expect(result.fee.unit_amount_cents).to eq(266)
        expect(result.fee.precise_unit_amount).to be_within(0.000000000000001).of(BigDecimal(40) / 15)
        expect(result.fee.amount_details["per_package_size"]).to eq(10)
      end
    end

    context "with a percentage rate model" do
      let(:rate_card) { create(:rate_card, organization:, currency: "USD") }
      let(:units) { 100 }
      let(:rate_model) { "percentage" }
      let(:rate_properties) { {"rate" => "10", "fixed_amount" => "2"} }

      it "prices the fee" do
        expect(result).to be_success
        expect(result.fee.amount_cents).to eq(1_200)
        expect(result.fee.unit_amount_cents).to eq(12)
        expect(result.fee.precise_unit_amount).to eq(BigDecimal(12) / 100)
        expect(result.fee.amount_details["rate"]).to eq("10.0")
      end
    end

    context "with a graduated percentage rate model" do
      let(:rate_card) { create(:rate_card, organization:, currency: "USD") }
      let(:rate_model) { "graduated_percentage" }
      let(:rate_properties) do
        {"graduated_percentage_ranges" => [
          {"from_value" => 0, "to_value" => 10, "rate" => "10", "flat_amount" => "2"},
          {"from_value" => 11, "to_value" => nil, "rate" => "5", "flat_amount" => "3"}
        ]}
      end

      it "prices the fee" do
        expect(result).to be_success
        expect(result.fee.amount_cents).to eq(625)
        expect(result.fee.unit_amount_cents).to eq(41)
        expect(result.fee.precise_unit_amount).to be_within(0.000000000000001).of(BigDecimal("6.25") / 15)
        expect(result.fee.amount_details["graduated_percentage_ranges"].count).to eq(2)
      end
    end
  end
end
