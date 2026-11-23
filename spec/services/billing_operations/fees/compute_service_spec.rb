# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::Fees::ComputeService do
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
    let(:pricing_unit) { nil }
    let(:billing_segment) do
      build(
        :billing_segment,
        organization:,
        contract:,
        customer:,
        contract_rate_card:,
        rate_card_rate:,
        rate_properties:,
        pricing_unit:,
        proration_ratio:,
        cycle_started_at: Time.utc(2026, 8, 1),
        started_at: Time.utc(2026, 8, 1),
        ended_at: BillingSegment.inclusive_end(Time.utc(2026, 9, 1))
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
        expect(result.fee).to have_attributes(contract:, contract_rate_card:)
        expect(result.fee.amount_currency).to eq("USD")
        expect(result.fee.properties).to eq(
          "from_datetime" => billing_segment.started_at.iso8601(6),
          "to_datetime" => billing_segment.ended_at.iso8601(6),
          "charges_from_datetime" => billing_segment.started_at.iso8601(6),
          "charges_to_datetime" => billing_segment.ended_at.iso8601(6),
          "charges_duration" => billing_segment.duration_in_days,
          "timestamp" => billing_segment.billing_at.iso8601(3),
          "fixed_charges_from_datetime" => nil,
          "fixed_charges_to_datetime" => nil,
          "fixed_charges_duration" => nil
        )
        expect(result.fee.subscription).to be_nil
        expect(result.fee.pay_in_advance).to be(false)
        expect(result.true_up_fee).to be_nil
      end

      context "with four configured term units" do
        let(:units) { 4 }

        it "uses the contract rate card's term quantity" do
          expect(result.fee.units).to eq(4)
          expect(result.fee.amount_cents).to eq(12_000)
        end

        context "when configured units are zero and a minimum applies" do
          let(:units) { 0 }
          let(:min_amount_cents) { 1_000 }

          it "retains the periodic minimum true-up" do
            expect(result).to be_success
            expect(result.fee.units).to eq(0)
            expect(result.true_up_fee.amount_cents).to eq(1_000)
          end
        end
      end

      it "looks up contract rate card units once when the association is not preloaded" do
        billing_segment

        statements = capture_sql { result }

        expect(result.fee.units).to eq(15)
        expect(statements.grep(/FROM "contract_rate_cards_terms"/i).size).to eq(1)
      end

      context "without a units row" do
        let(:units) { nil }

        it "memoizes the missing units lookup" do
          billing_segment

          statements = capture_sql { result }

          expect(result.fee.units).to eq(BigDecimal(0))
          expect(statements.grep(/FROM "contract_rate_cards_terms"/i).size).to eq(1)
        end
      end

      context "when multiple units rows exist" do
        before do
          create(
            :contract_rate_card_term,
            organization:,
            contract_rate_card:,
            units: 7,
            effective_date: Date.new(2026, 7, 1)
          )
        end

        it "uses the first effective units row" do
          expect(result).to be_success
          expect(result.fee.units).to eq(7)
          expect(result.fee.amount_cents).to eq(21_000)
        end
      end

      context "with an advance rate card" do
        let(:rate_card) { create(:rate_card, :advance, organization:, product: fixed_product, currency: "USD") }

        it "stores the advance billing timing on the fee" do
          expect(result.fee.pay_in_advance).to be(true)
        end
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
          expect(result.true_up_fee.properties).to eq(result.fee.properties)
          expect(result.true_up_fee.properties).not_to have_key("billing_segment_id")
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
          billing_segment.started_at = Time.utc(2026, 8, 20)
          billing_segment.ended_at = BillingSegment.inclusive_end(Time.utc(2026, 8, 30))

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
            billing_segment.cycle_started_at = Time.utc(2026, 8, 1, 4)
            billing_segment.started_at = Time.utc(2026, 8, 1, 4)
            billing_segment.ended_at = BillingSegment.inclusive_end(Time.utc(2026, 9, 1, 4))

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

        context "when prorated over a partial period" do
          let(:rate_card) { create(:rate_card, organization:, product: fixed_product, currency: "USD", proration: true) }
          let(:proration_ratio) { BigDecimal("30") / 31 }
          let(:flat_amounts) { %w[0.00 0.00] }
          let(:rate_properties) do
            {"graduated_ranges" => [
              {"from_value" => 0, "to_value" => 3, "per_unit_amount" => "10.00", "flat_amount" => flat_amounts[0]},
              {"from_value" => 4, "to_value" => nil, "per_unit_amount" => "6.00", "flat_amount" => flat_amounts[1]}
            ]}
          end

          it "allocates full units to tiers before prorating each tier" do
            expect(result).to be_success
            expect(result.fee.amount_cents).to eq(4_065)
            expect(result.fee.precise_amount_cents).to be_within(0.000001).of(BigDecimal("4200") * billing_segment.proration_ratio)
            expect(result.fee.amount_details["graduated_ranges"].map { |tier| tier["units"].to_d }).to eq(
              [3, 2].map { |tier_units| tier_units * billing_segment.proration_ratio }
            )
          end

          context "with flat fees in both tiers" do
            let(:flat_amounts) { %w[5.00 2.00] }

            it "keeps reached-tier flat fees whole" do
              expect(result).to be_success
              expect(result.fee.amount_cents).to eq(4_765)
              expect(result.fee.precise_amount_cents).to be_within(0.000001).of(
                BigDecimal("4200") * billing_segment.proration_ratio + 700
              )
              expect(result.fee.amount_details["graduated_ranges"].map { |tier| tier["flat_unit_amount"] }).to eq(%w[5.0 2.0])
            end

            context "when weighted units would not reach the second tier" do
              let(:proration_ratio) { BigDecimal("0.5") }

              it "still charges the second tier's prorated units and whole flat fee" do
                expect(result.fee.amount_cents).to eq(2_800)
                expect(result.fee.amount_details["graduated_ranges"].map { |tier| tier["units"].to_d }).to eq([1.5, 1])
              end
            end
          end
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

      context "when decimal proration is just above a package boundary" do
        let(:package_metric) { create(:sum_billable_metric, organization:, field_name: "amount", recurring: true) }
        let(:package_product) { create(:product, :metered, organization:, billable_metric: package_metric) }
        let(:rate_card) do
          create(:rate_card, organization:, product: package_product, currency: "USD")
        end
        let(:units) { 3 }
        let(:proration_ratio) { 20.fdiv(30) }
        let(:rate_properties) { {"amount" => "20", "free_units" => 0, "package_size" => 1} }

        it "preserves the legacy decimal scale before rounding packages up" do
          expect(result).to be_success
          expect(result.fee.amount_cents).to eq(6_000)
          expect(result.fee.units).to eq(3)
        end
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
