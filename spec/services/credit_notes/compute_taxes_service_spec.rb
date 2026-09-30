# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::ComputeTaxesService do
  subject(:compute_result) { described_class.call(credit_note:, adjust_rounding:) }

  let(:adjust_rounding) { false }
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, organization:, customer:, version_number: 3) }
  let(:fee_amount_cents) { 100 }
  let(:fee_coupons_amount_cents) { 0 }
  let(:fee_tax_amount_cents) { 20 }
  let(:item_amount_cents) { 50 }
  let(:taxes) { [create(:tax, organization:, code: "vat", rate: 20)] }
  let(:invoice_tax_code) { nil }
  let(:credit_note) { create(:credit_note, invoice:, customer:, taxes_amount_cents: 0, precise_taxes_amount_cents: 0) }
  let(:fee) do
    create(
      :fee,
      invoice:,
      amount_cents: fee_amount_cents,
      precise_amount_cents: fee_amount_cents,
      precise_coupons_amount_cents: fee_coupons_amount_cents,
      taxes_rate: taxes.sum(&:rate)
    )
  end

  before do
    taxes.each do |tax|
      create(:fee_applied_tax, fee:, tax:, tax_code: tax.code, tax_rate: tax.rate, amount_cents: fee_tax_amount_cents, precise_amount_cents: fee_tax_amount_cents)
      create(:invoice_applied_tax, invoice:, tax:, tax_code: invoice_tax_code || tax.code, tax_rate: tax.rate, amount_cents: fee_tax_amount_cents, fees_amount_cents: fee_amount_cents)
    end
    create(:credit_note_item, credit_note:, fee:, amount_cents: item_amount_cents, precise_amount_cents: item_amount_cents)
    credit_note.reload
  end

  it "sets the credit note taxes from the credited items" do
    expect(compute_result).to be_success
    expect(credit_note).to have_attributes(taxes_amount_cents: 10, precise_taxes_amount_cents: 10, taxes_rate: 20, coupons_adjustment_amount_cents: 0)
    expect(credit_note.applied_taxes.map { |tax| [tax.tax_code, tax.amount_cents] }).to eq([["vat", 10]])
  end

  context "with a coupon on the fee" do
    let(:fee_coupons_amount_cents) { 20 }

    it "taxes the credited amount after its share of the coupon" do
      expect(compute_result.coupons_adjustment_amount_cents).to eq(10)
      expect(credit_note).to have_attributes(precise_coupons_adjustment_amount_cents: 10, coupons_adjustment_amount_cents: 10, taxes_amount_cents: 8)
    end
  end

  context "when the credit note takes the rest of the invoice" do
    let(:adjust_rounding) { true }

    before do
      create(:credit_note, invoice:, customer:, taxes_amount_cents: 11, precise_taxes_amount_cents: 10.5)
    end

    it "subtracts the rounding taken by earlier credit notes" do
      expect(compute_result).to be_success
      expect(credit_note).to have_attributes(precise_taxes_amount_cents: 9.5, taxes_amount_cents: 10)
    end
  end

  context "when a fee tax has no matching invoice tax" do
    let(:invoice_tax_code) { "other" }

    it "returns the apply taxes failure" do
      expect(compute_result).to be_failure
      expect(compute_result.error.code).to eq("invoice_applied_tax_not_found")
    end
  end
end
