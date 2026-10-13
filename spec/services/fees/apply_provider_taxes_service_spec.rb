# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::ApplyProviderTaxesService do
  subject(:apply_service) { described_class.new(fee:, fee_taxes:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) { create(:invoice, organization:, customer:) }

  let(:fee) do
    create(:fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000.0, precise_coupons_amount_cents:,
      taxes_amount_cents: 0, taxes_precise_amount_cents: 0.0, taxes_rate: 0, taxes_base_rate: 0.0)
  end
  let(:precise_coupons_amount_cents) { 0 }

  let(:fee_taxes) do
    build(:tax_result,
      tax_amount_cents: 170,
      tax_breakdown: [
        build(:tax_breakdown_item, name: "tax 2", type: "type2", rate: "0.12", tax_amount: 120),
        build(:tax_breakdown_item, name: "tax 3", type: "type3", rate: "0.05", tax_amount: 50)
      ])
  end

  before do
    fee_taxes
  end

  describe "call" do
    context "when jurisdictions have different taxable base reductions" do
      let(:fee_taxes) do
        build(:tax_result,
          tax_amount_cents: 146,
          tax_breakdown: [
            build(:tax_breakdown_item, name: "State tax", type: "tax", rate: "0.12", tax_amount: 96),
            build(:tax_breakdown_item, name: "City tax", type: "tax", rate: "0.05", tax_amount: 50)
          ])
      end

      it "stores the provider allocation in both tax amount columns" do
        result = apply_service.call

        expect(result).to be_success
        expect(result.applied_taxes.map { |tax| [tax.amount_cents, tax.precise_amount_cents] })
          .to eq([[96, 96.to_d], [50, 50.to_d]])
        expect(fee).to have_attributes(taxes_amount_cents: 146, taxes_precise_amount_cents: 146.to_d)
      end

      context "when the fee is not persisted" do
        let(:fee) { build(:fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000) }

        it "keeps the precise total equal to the provider total without persisting taxes" do
          result = apply_service.call

          expect(result).to be_success
          expect(result.applied_taxes).to all(be_new_record)
          expect(fee).to have_attributes(taxes_amount_cents: 146, taxes_precise_amount_cents: 146.to_d)
        end
      end
    end

    context "when the provider breakdown contains fractional cents" do
      let(:fee_taxes) do
        build(:tax_result,
          tax_amount_cents: 8,
          tax_breakdown: %w[State County City].map do |name|
            build(:tax_breakdown_item, name:, type: "tax", rate: "0.025", tax_amount: 2.5)
          end)
      end

      it "preserves fractional cents separately from the booked allocation" do
        result = apply_service.call

        expect(result.applied_taxes.map { |tax| [tax.amount_cents, tax.precise_amount_cents] })
          .to eq([[3, 2.5.to_d], [3, 2.5.to_d], [2, 2.5.to_d]])
        expect(fee).to have_attributes(taxes_amount_cents: 8, taxes_precise_amount_cents: 7.5.to_d)
      end
    end

    context "when there is no applied taxes yet" do
      it "creates applied_taxes based on the provider taxes" do
        result = apply_service.call

        expect(result).to be_success

        applied_taxes = result.applied_taxes
        expect(applied_taxes.count).to eq(2)

        expect(applied_taxes.map(&:tax_code)).to contain_exactly("tax_2", "tax_3")
        expect(fee).to have_attributes(taxes_amount_cents: 170, taxes_precise_amount_cents: 170.0, taxes_rate: 17)
      end

      context "when there is tax deduction" do
        let(:fee_taxes) do
          build(:tax_result,
            tax_amount_cents: 136,
            tax_breakdown: [
              build(:tax_breakdown_item, name: "tax 2", type: "type2", rate: "0.12", tax_amount: 96),
              build(:tax_breakdown_item, name: "tax 3", type: "type3", rate: "0.05", tax_amount: 40)
            ])
        end

        it "creates applied_taxes based on the provider taxes" do
          result = apply_service.call

          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(2)

          expect(applied_taxes.map(&:tax_code)).to contain_exactly("tax_2", "tax_3")
          expect(fee).to have_attributes(
            taxes_amount_cents: 136,
            taxes_precise_amount_cents: 136.0,
            taxes_rate: 17,
            taxes_base_rate: 0.8
          )
        end
      end

      context "when taxes are paid by the seller" do
        let(:fee_taxes) do
          build(:tax_result,
            tax_amount_cents: 0,
            tax_breakdown: [build(:tax_breakdown_item, name: "Tax", type: "tax", rate: "0.00", tax_amount: 0)])
        end

        it "does not create applied_taxes" do
          result = apply_service.call

          expect(result).to be_success

          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(1)
          expect(fee).to have_attributes(
            taxes_amount_cents: 0,
            taxes_precise_amount_cents: 0.0,
            taxes_rate: 0
          )
        end
      end
    end

    context "when the fee has no entry in the provider response" do
      let(:fee_taxes) { nil }

      context "when the fee has no amount" do
        let(:fee) do
          create(:fee, invoice:, amount_cents: 0, precise_amount_cents: 0.0, precise_coupons_amount_cents:,
            taxes_amount_cents: 0, taxes_precise_amount_cents: 0.0, taxes_rate: 0, taxes_base_rate: 0.0)
        end

        it "leaves the fee untaxed" do
          result = apply_service.call

          expect(result).to be_success
          expect(result.applied_taxes).to be_empty
          expect(fee.applied_taxes).to be_empty
          expect(fee).to have_attributes(taxes_amount_cents: 0, taxes_rate: 0)
        end
      end

      it "fails rather than leaving a fee with an amount untaxed" do
        result = apply_service.call

        expect(result).not_to be_success
        expect(result.error.code).to eq("fee_missing_from_tax_response")
      end

      it "does not apply taxes to a fee with an amount" do
        apply_service.call

        expect(fee.applied_taxes).to be_empty
        expect(fee).to have_attributes(taxes_amount_cents: 0, taxes_rate: 0)
      end
    end

    context "when fee already have taxes" do
      before { create(:fee_applied_tax, fee:) }

      it "does not re-apply taxes" do
        expect do
          result = apply_service.call

          expect(result).to be_success
        end.not_to change { fee.applied_taxes.count }
      end
    end

    context "when applying taxes with specific provider rules" do
      special_rules =
        [
          {received_type: "notCollecting", expected_name: "Not collecting", tax_code: "not_collecting"},
          {received_type: "productNotTaxed", expected_name: "Product not taxed", tax_code: "product_not_taxed"},
          {received_type: "jurisNotTaxed", expected_name: "Juris not taxed", tax_code: "juris_not_taxed"}
        ]
      special_rules.each do |applied_rule|
        context "when tax provider returned specific rule applied to fees - #{applied_rule[:expected_name]}" do
          let(:fee_taxes) do
            build(:tax_result,
              tax_amount_cents: 0,
              tax_breakdown: [
                build(:tax_breakdown_item, name: applied_rule[:expected_name], type: applied_rule[:received_type], rate: "0.00", tax_amount: 0)
              ])
          end

          it "creates applied_taxes based on the provider rules" do
            result = apply_service.call

            expect(result).to be_success

            applied_taxes = result.applied_taxes
            expect(applied_taxes.count).to eq(1)

            applied_tax = applied_taxes.first
            expect(applied_tax).to have_attributes(
              tax_code: applied_rule[:tax_code],
              tax_name: applied_rule[:expected_name],
              tax_description: applied_rule[:received_type]
            )
            expect(fee).to have_attributes(taxes_amount_cents: 0, taxes_precise_amount_cents: 0.0, taxes_rate: 0)
          end
        end
      end
    end
  end
end
