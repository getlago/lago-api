# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::AmountsService do
  subject(:result) { described_class.call(currency:, charge_model_result:, **options) }

  let(:currency) { Money::Currency.new("USD") }
  let(:charge_model_result) { model_result }
  let(:model_result) do
    ChargeModels::BaseService::Result.new.tap do |model_result|
      model_result.amount = model_result.unit_amount = value
      model_result.units = units
    end
  end
  let(:value) { "0.3333".to_d }
  let(:units) { 1.to_d }
  let(:options) { {} }

  describe "option values" do
    [described_class::Deduction, described_class::TrueUp, described_class::AppliedPricingUnit].each do |type|
      it "represents absent #{type.name.demodulize} with an immutable none value" do
        expect(type.none).to be_none
        expect(type.none).to be_frozen
      end
    end

    it "distinguishes zero monetary values from absence" do
      expect(described_class::Deduction.new(amount_cents: 0, billed_days: 1, period_days: 1)).not_to be_none
      expect(described_class::TrueUp.new(minimum_amount_cents: 0)).not_to be_none
      expect(described_class::AppliedPricingUnit.from_pricing_unit(pricing_unit: build(:pricing_unit), conversion_rate: 0.to_d)).not_to be_none
    end

    it "normalizes absent pricing units" do
      expect(described_class::AppliedPricingUnit.from_applied_pricing_unit(nil)).to eq(described_class::AppliedPricingUnit.none)
      expect(described_class::AppliedPricingUnit.from_pricing_unit(pricing_unit: nil, conversion_rate: 0.25)).to eq(described_class::AppliedPricingUnit.none)
    end

    it "builds options from a pricing unit and conversion rate" do
      pricing_unit = build(:pricing_unit)
      options = described_class::AppliedPricingUnit.from_pricing_unit(pricing_unit:, conversion_rate: 0.25.to_d)

      expect(options).to have_attributes(pricing_unit:, conversion_rate: 0.25.to_d)
      expect(options).not_to be_none
      expect(options).to be_frozen
    end

    it "copies actual pricing-unit options" do
      actual = build(:applied_pricing_unit, conversion_rate: 0.25)
      options = described_class::AppliedPricingUnit.from_applied_pricing_unit(actual)

      expect(options).to have_attributes(pricing_unit: actual.pricing_unit, conversion_rate: actual.conversion_rate)
      expect(options).not_to be_none
      expect(options).to be_frozen
    end

    it "rounds the prorated deduction to integer cents" do
      deduction = described_class::Deduction.new(amount_cents: 100, billed_days: 2, period_days: 3)

      expect(deduction.prorated_amount_cents).to eq(67)
    end

    it "preserves fractional cents in the prorated minimum" do
      true_up = described_class::TrueUp.new(minimum_amount_cents: 100, billed_days: 2, period_days: 3)

      expect(true_up.prorated_minimum_amount_cents).to eq(100.fdiv(3) * 2)
    end

    it "exposes the pricing unit's decimal subunit factor" do
      options = described_class::AppliedPricingUnit.from_applied_pricing_unit(build(:applied_pricing_unit))

      expect(options.subunit_to_unit).to eq(100.to_d)
      expect(options.subunit_to_unit).to be_a(BigDecimal)
    end
  end

  describe "#call" do
    [nil, BaseResult.new, {amount: 1, unit_amount: 1, units: 1}].each do |invalid_result|
      context "with a #{invalid_result.class} charge model result" do
        let(:charge_model_result) { invalid_result }

        it "rejects results that are not charge model results" do
          expect { result }.to raise_error(
            ArgumentError,
            "charge_model_result must be a ChargeModels::BaseService::Result or Charges::ApplyPayInAdvanceChargeModelService::Result"
          )
        end
      end
    end

    context "with a charge model result subclass" do
      let(:charge_model_result) do
        Class.new(ChargeModels::BaseService::Result).new.tap do |model_result|
          model_result.amount = model_result.unit_amount = value
          model_result.units = units
        end
      end

      it "accepts the result without mutating it" do
        expect(result).to be_success
        expect(result.amount).to have_attributes(amount_cents: 33, precise_amount_cents: 33.33.to_d)
        expect(charge_model_result).to have_attributes(amount: value, unit_amount: value, units:)
      end
    end

    context "with a pay-in-advance result" do
      let(:charge_model_result) do
        Charges::ApplyPayInAdvanceChargeModelService::Result.new.tap do |advance_result|
          advance_result.amount = value
          advance_result.precise_amount = precise_value
          advance_result.unit_amount = unit_value
          advance_result.units = units
        end
      end
      let(:value) { 101.to_d }
      let(:precise_value) { "100.8".to_d }
      let(:unit_value) { "0.336".to_d }

      it "retains minor-unit totals and separate precision without scaling or rounding again" do
        expect(result).to be_success
        expect(result.amount).to be_frozen
        expect(result.amount).to have_attributes(
          amount_cents: 101, precise_amount_cents: precise_value,
          unit_amount_cents: 33.6.to_d, precise_unit_amount: unit_value, pricing_unit_usage: nil
        )
        expect(Fee.new(unit_amount_cents: result.amount.unit_amount_cents).unit_amount_cents).to eq(33)
        expect(charge_model_result).to have_attributes(amount: value, precise_amount: precise_value, unit_amount: unit_value, units:)
        expect(result.true_up_amount).to be_nil
      end

      [
        ["0", "0.4", "0", "0"],
        ["101", "100.8", "0.336", "0"],
        ["101", "100.8", "-0.336", "-3"],
        ["-101", "-100.8", "-0.336", "3"]
      ].each do |total, precise, unit, usage|
        context "with total #{total} and units #{usage}" do
          let(:value) { total.to_d }
          let(:precise_value) { precise.to_d }
          let(:unit_value) { unit.to_d }
          let(:units) { usage.to_d }

          it "preserves zero and negative values without standard-model clamping" do
            expect(result.amount).to have_attributes(
              amount_cents: value, precise_amount_cents: precise_value,
              unit_amount_cents: unit_value * 100, precise_unit_amount: unit_value, pricing_unit_usage: nil
            )
          end
        end
      end

      context "with pricing units" do
        let(:options) do
          {applied_pricing_unit: described_class::AppliedPricingUnit.from_applied_pricing_unit(
            build(:applied_pricing_unit, pricing_unitable: nil, conversion_rate: 0.25)
          )}
        end

        [
          ["USD", "101", "0.336", "25", "25.25", "8.25", "0.0825", 33],
          ["JPY", "101", "0.336", "0", "0.2525", "0.0825", "0.0825", 33],
          ["USD", "0", "0", "0", "0", "0", "0", 0],
          ["USD", "-101", "-0.336", "-25", "-25.25", "-8.25", "-0.0825", -33]
        ].each do |code, total, unit, rounded, precise, unit_cents, precise_unit, usage_unit_cents|
          context "with #{total} pricing-unit cents in #{code}" do
            let(:currency) { Money::Currency.new(code) }
            let(:value) { total.to_d }
            let(:unit_value) { unit.to_d }
            let(:units) { -3.to_d }

            it "converts the rounded total using pricing-unit subunits and retains unit truncation" do
              expect(result.amount).to have_attributes(
                amount_cents: rounded.to_d, precise_amount_cents: precise.to_d,
                unit_amount_cents: unit_cents.to_d, precise_unit_amount: precise_unit.to_d
              )
              expect(result.amount.pricing_unit_usage).to be_new_record.and have_attributes(
                amount_cents: value, precise_amount_cents: value,
                unit_amount_cents: usage_unit_cents, precise_unit_amount: unit_value
              )
            end
          end
        end
      end
    end

    context "with explicit absent options" do
      let(:options) do
        {
          applied_pricing_unit: described_class::AppliedPricingUnit.none,
          deduction: described_class::Deduction.none,
          true_up: described_class::TrueUp.none
        }
      end

      it "returns the base amount without deductions, pricing-unit usage, or a true-up" do
        expect(result.amount).to have_attributes(amount_cents: 33, precise_amount_cents: 33.33.to_d, pricing_unit_usage: nil)
        expect(result.true_up_amount).to be_nil
      end
    end

    context "with an empty charge model result" do
      let(:charge_model_result) { ChargeModels::BaseService::Result.new }

      it "returns no amounts and leaves the empty result unchanged" do
        expect(result).to be_success
        expect(result.amount).to be_nil
        expect(result.true_up_amount).to be_nil
        expect(charge_model_result).to have_attributes(amount: nil, unit_amount: nil, units: nil)
      end
    end

    [
      ["USD", "0.3333", 33, "33.33", 33],
      ["USD", "0.336", 34, "33.6", 33],
      ["USD", "0.50125", 50, "50.125", 50],
      ["JPY", "0.3333", 0, "0.3333", 0],
      ["JPY", "0.336", 0, "0.336", 0],
      ["JPY", "0.50125", 1, "0.50125", 0],
      ["KWD", "0.3333", 333, "333.3", 333],
      ["KWD", "0.336", 336, "336", 336],
      ["KWD", "0.50125", 501, "501.25", 501]
    ].each do |currency_code, input, rounded, precise, unit_cents|
      context "with #{input} #{currency_code}" do
        let(:currency) { Money::Currency.new(currency_code) }
        let(:value) { input.to_d }

        it "rounds the total but leaves unit cents for the fee's implicit truncation" do
          expect(result).to be_success
          expect(result.amount).to have_attributes(
            amount_cents: rounded,
            precise_amount_cents: precise.to_d,
            unit_amount_cents: precise.to_d,
            precise_unit_amount: value,
            pricing_unit_usage: nil
          )
          expect(Fee.new(**result.amount.to_h)).to have_attributes(
            amount_cents: rounded,
            precise_amount_cents: precise.to_d,
            unit_amount_cents: unit_cents,
            precise_unit_amount: value
          )
          expect(result.true_up_amount).to be_nil
        end
      end
    end

    context "with distinct total and unit amounts" do
      let(:units) { 3.to_d }

      before { model_result.amount = "0.9999".to_d }

      it "converts each model amount independently" do
        expect(result.amount).to have_attributes(
          amount_cents: 100, precise_amount_cents: 99.99.to_d, unit_amount_cents: 33.33.to_d, precise_unit_amount: value
        )
      end
    end

    context "with zero usage" do
      let(:units) { 0.to_d }

      it "retains the model's flat amount and unit price" do
        expect(result.amount).to have_attributes(amount_cents: 33, unit_amount_cents: 33.33.to_d, precise_unit_amount: value)
      end

      context "with a zero amount" do
        let(:value) { 0.to_d }

        it "returns zero monetary fields" do
          expect(result.amount).to have_attributes(
            amount_cents: 0, precise_amount_cents: 0, unit_amount_cents: 0, precise_unit_amount: 0
          )
          expect(charge_model_result).to have_attributes(amount: 0, unit_amount: 0, units: 0)
        end
      end
    end

    context "with negative units" do
      let(:units) { -1.to_d }

      it "normalizes monetary fields without mutating the charge model result" do
        expect(result.amount).to have_attributes(
          amount_cents: 0, precise_amount_cents: 0, unit_amount_cents: 0, precise_unit_amount: 0
        )
        expect(charge_model_result).to have_attributes(amount: value, unit_amount: value, units: -1)
      end
    end

    context "with a negative amount" do
      let(:value) { -1.to_d }

      it "normalizes monetary fields without mutating the charge model result" do
        expect(result.amount).to have_attributes(
          amount_cents: 0, precise_amount_cents: 0, unit_amount_cents: 0, precise_unit_amount: 0
        )
        expect(charge_model_result).to have_attributes(amount: value, unit_amount: value, units:)
      end
    end

    context "with an already-paid fee" do
      let(:value) { "1.006".to_d }
      let(:options) { {deduction: described_class::Deduction.new(amount_cents: 100, billed_days: 2, period_days: 3)} }

      it "prorates and rounds the deduction without changing the unit price" do
        expect(result.amount).to have_attributes(
          amount_cents: 34, precise_amount_cents: 33.6.to_d, unit_amount_cents: 100.6.to_d, precise_unit_amount: value
        )
      end

      context "with zero already paid" do
        let(:options) { {deduction: described_class::Deduction.new(amount_cents: 0, billed_days: 2, period_days: 3)} }

        it "retains the full rounded and precise totals" do
          expect(result.amount).to have_attributes(amount_cents: 101, precise_amount_cents: 100.6.to_d)
        end
      end

      context "when the deduction exceeds the total" do
        let(:value) { "0.5".to_d }

        it "clamps both totals independently to zero" do
          expect(result.amount).to have_attributes(
            amount_cents: 0, precise_amount_cents: 0, unit_amount_cents: 50, precise_unit_amount: value
          )
        end
      end

      context "when only the precise total is below the deduction" do
        let(:value) { "0.666".to_d }

        it "does not leave a negative precise total" do
          expect(result.amount).to have_attributes(amount_cents: 0, precise_amount_cents: 0)
        end
      end

      context "when a precise remainder survives a zero rounded total" do
        let(:value) { "0.674".to_d }

        it "retains the precise remainder" do
          expect(result.amount).to have_attributes(amount_cents: 0, precise_amount_cents: 0.4.to_d)
        end
      end
    end

    context "with a minimum" do
      let(:options) { {true_up: described_class::TrueUp.new(minimum_amount_cents: 100)} }

      it "calculates amount and true-up from separate rounded and precise totals" do
        expect(result.amount.amount_cents).to eq(33)
        expect(result.true_up_amount).to have_attributes(
          amount_cents: 67, precise_amount_cents: 66.67.to_d, unit_amount_cents: 67, precise_unit_amount: 0.6667.to_d
        )
      end

      context "with explicit grouped usage totals" do
        let(:options) do
          {true_up: described_class::TrueUp.new(minimum_amount_cents: 100, used_amount_cents: 66, used_precise_amount_cents: 66.66.to_d)}
        end

        it "uses grouped totals instead of the individual amount for the true-up" do
          expect(result.amount.amount_cents).to eq(33)
          expect(result.true_up_amount).to have_attributes(amount_cents: 34, precise_amount_cents: 33.34.to_d)
        end
      end

      context "when rounded usage meets the minimum but precise usage does not" do
        let(:value) { "0.996".to_d }

        it "does not create a true-up" do
          expect(result.true_up_amount).to be_nil
        end
      end

      context "when usage exceeds the minimum" do
        let(:value) { 2.to_d }

        it "does not create a true-up" do
          expect(result.true_up_amount).to be_nil
        end
      end

      context "with a zero minimum" do
        let(:options) { {true_up: described_class::TrueUp.new(minimum_amount_cents: 0)} }

        it "does not create a true-up" do
          expect(result.true_up_amount).to be_nil
        end
      end
    end

    context "with only grouped usage totals" do
      let(:charge_model_result) { ChargeModels::BaseService::Result.new }
      let(:options) do
        {true_up: described_class::TrueUp.new(minimum_amount_cents: 100, used_amount_cents: 66, used_precise_amount_cents: 66.66.to_d)}
      end

      it "returns only a true-up, not a synthetic base amount" do
        expect(result.amount).to be_nil
        expect(result.true_up_amount).to have_attributes(
          amount_cents: 34, precise_amount_cents: 33.34.to_d, unit_amount_cents: 34, precise_unit_amount: 0.3334.to_d
        )
        expect(charge_model_result).to have_attributes(amount: nil, unit_amount: nil, units: nil)
      end

      context "with a fractional prorated minimum" do
        let(:options) do
          {true_up: described_class::TrueUp.new(
            minimum_amount_cents: 1000, billed_days: 15, period_days: 31, used_amount_cents: 200, used_precise_amount_cents: 200.to_d
          )}
        end

        it "does not round the minimum before computing the difference" do
          expect(result.true_up_amount).to have_attributes(
            amount_cents: 284,
            precise_amount_cents: "283.8709677419355".to_d,
            unit_amount_cents: 284,
            precise_unit_amount: "2.838709677419355".to_d
          )
        end
      end

      context "with a positive difference below half a cent" do
        let(:options) do
          {true_up: described_class::TrueUp.new(
            minimum_amount_cents: 100, billed_days: 1, period_days: 16, used_amount_cents: 6, used_precise_amount_cents: 6.6.to_d
          )}
        end

        it "retains a zero-rounded true-up and its negative precise difference" do
          expect(result.true_up_amount.amount_cents).to eq(0)
          expect(result.true_up_amount.precise_amount_cents).to eq("-0.35".to_d)
        end
      end

      ["JPY", "KWD"].each do |currency_code|
        context "with #{currency_code}" do
          let(:currency) { Money::Currency.new(currency_code) }

          it "uses the fiat subunit for the precise unit amount" do
            expect(result.true_up_amount).to have_attributes(
              amount_cents: 34, precise_amount_cents: 33.34.to_d,
              unit_amount_cents: 34, precise_unit_amount: 33.34.to_d / currency.subunit_to_unit
            )
          end
        end
      end
    end

    context "with pricing units" do
      let(:pricing_unit) { build(:pricing_unit) }
      let(:applied_pricing_unit) do
        described_class::AppliedPricingUnit.from_applied_pricing_unit(build(:applied_pricing_unit, pricing_unit:, pricing_unitable: nil, conversion_rate: 0.25))
      end
      let(:options) { {applied_pricing_unit:} }
      let(:value) { "0.336".to_d }

      it "preserves the pricing-unit rounding and implicit unit-cent truncation before fiat conversion" do
        expect(result.amount).to have_attributes(
          amount_cents: 9, precise_amount_cents: 8.5.to_d, unit_amount_cents: 8.25.to_d, precise_unit_amount: 0.0825.to_d
        )
        expect(result.amount.pricing_unit_usage).to be_new_record.and have_attributes(
          amount_cents: 34, precise_amount_cents: 33.6.to_d, unit_amount_cents: 33, precise_unit_amount: value
        )
        expect(Fee.new(**result.amount.to_h).unit_amount_cents).to eq(8)
      end

      context "with zero units and a flat price" do
        let(:units) { 0.to_d }

        it "retains both pricing-unit and fiat unit amounts" do
          expect(result.amount.precise_unit_amount).to eq(0.0825.to_d)
          expect(result.amount.pricing_unit_usage.precise_unit_amount).to eq(value)
        end
      end

      context "with a negative amount" do
        let(:value) { -1.to_d }

        it "normalizes pricing-unit and fiat monetary fields" do
          expect(result.amount).to have_attributes(amount_cents: 0, precise_amount_cents: 0, unit_amount_cents: 0, precise_unit_amount: 0)
          expect(result.amount.pricing_unit_usage).to have_attributes(
            amount_cents: 0, precise_amount_cents: 0, unit_amount_cents: 0, precise_unit_amount: 0
          )
        end
      end

      context "with a minimum" do
        let(:options) { {applied_pricing_unit:, true_up: described_class::TrueUp.new(minimum_amount_cents: 100)} }

        it "compares the minimum to pricing-unit usage rather than fiat usage" do
          expect(result.true_up_amount).to have_attributes(
            amount_cents: 17, precise_amount_cents: 16.5.to_d, unit_amount_cents: 16.5.to_d, precise_unit_amount: 0.165.to_d
          )
          expect(result.true_up_amount.pricing_unit_usage).to have_attributes(
            amount_cents: 66, precise_amount_cents: 66, unit_amount_cents: 66, precise_unit_amount: 0.664.to_d
          )
        end

        context "when pricing-unit usage meets the minimum but fiat usage does not" do
          let(:value) { 1.to_d }

          it "does not create a true-up" do
            expect(result.amount.amount_cents).to eq(25)
            expect(result.true_up_amount).to be_nil
          end
        end
      end

      context "with grouped totals and a fractional minimum" do
        let(:charge_model_result) { ChargeModels::BaseService::Result.new }
        let(:options) do
          {
            applied_pricing_unit:,
            true_up: described_class::TrueUp.new(
              minimum_amount_cents: 1000, billed_days: 15, period_days: 31,
              used_amount_cents: 200, used_precise_amount_cents: 200.6.to_d
            )
          }
        end

        it "converts rounded and precise differences separately using pricing-unit subunits" do
          expect(result.amount).to be_nil
          expect(result.true_up_amount).to have_attributes(
            amount_cents: 71, precise_amount_cents: 71, unit_amount_cents: 70.75.to_d, precise_unit_amount: 0.7075.to_d
          )
          expect(result.true_up_amount.pricing_unit_usage).to have_attributes(
            amount_cents: 284, precise_amount_cents: "283.8709677419355".to_d,
            unit_amount_cents: 283, precise_unit_amount: "2.832709677419355".to_d
          )
        end
      end
    end
  end
end
