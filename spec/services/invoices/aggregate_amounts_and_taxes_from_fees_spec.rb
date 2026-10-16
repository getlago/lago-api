# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::AggregateAmountsAndTaxesFromFees do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, invoice_type: :advance_charges, customer:) }
  let(:tax_5) { create(:tax, rate: 5, name: "VAT", description: "VAT 5%", code: "tax-1234") }
  let(:tax_12) { create(:tax, rate: 12, name: "VAT", description: "VAT 12%", code: "tax-8901") }

  it do
    fee1 = create(:charge_fee, :succeeded, invoice:, amount_cents: 200, taxes_amount_cents: 9)
    fee2 = create(:charge_fee, :succeeded, invoice:, amount_cents: 50, taxes_amount_cents: 1)
    fee3 = create(:charge_fee, :succeeded, invoice:, amount_cents: 120, taxes_amount_cents: 23)

    create(:fee_applied_tax, fee: fee1, tax: tax_5, tax_name: tax_5.name, tax_description: tax_5.description, tax_rate: tax_5.rate, amount_cents: 16)
    create(:fee_applied_tax, fee: fee2, tax: tax_12, tax_name: tax_12.name, tax_description: tax_12.description, tax_rate: tax_12.rate, amount_cents: 2)
    create(:fee_applied_tax, fee: fee3, tax: tax_5, tax_name: tax_5.name, tax_description: tax_5.description, tax_rate: tax_5.rate, amount_cents: 9)
    create(:fee_applied_tax, fee: fee3, tax: tax_12, tax_name: tax_12.name, tax_description: tax_12.description, tax_rate: tax_12.rate, amount_cents: 11)

    described_class.call(invoice:)

    expect(invoice.fees_amount_cents).to eq(200 + 50 + 120)
    # if we compute taxes: 200 * 0.05 + 50 * 0.12 + 120 * 0.05 + 120 * 0.12 = 36.4
    # but this service sums already computed taxes
    expect(invoice.taxes_amount_cents).to eq(9 + 1 + 23)
    expect(invoice.total_amount_cents).to eq(200 + 50 + 120 + 33)
    expect(invoice.sub_total_excluding_taxes_amount_cents).to eq invoice.fees_amount_cents
    expect(invoice.sub_total_including_taxes_amount_cents).to eq invoice.total_amount_cents

    expect(invoice.applied_taxes.count).to eq 2
    applied_tax_5 = invoice.applied_taxes.find { |at| at.tax_code == tax_5.code }
    expect(applied_tax_5.tax_name).to eq tax_5.name
    expect(applied_tax_5.tax_description).to eq tax_5.description
    expect(applied_tax_5.tax_rate).to eq tax_5.rate
    expect(applied_tax_5.amount_cents).to eq(9 + 16)
    expect(applied_tax_5.fees_amount_cents).to eq(200 + 120)
    expect(applied_tax_5.taxable_base_amount_cents).to eq(200 + 120)

    applied_tax_12 = invoice.applied_taxes.find { |at| at.tax_code == tax_12.code }
    expect(applied_tax_12.tax_name).to eq tax_12.name
    expect(applied_tax_12.tax_description).to eq tax_12.description
    expect(applied_tax_12.tax_rate).to eq tax_12.rate
    expect(applied_tax_12.amount_cents).to eq(2 + 11)
    expect(applied_tax_12.fees_amount_cents).to eq(120 + 50)
    expect(applied_tax_12.taxable_base_amount_cents).to eq(120 + 50)
  end

  context "with multiple provider jurisdictions" do
    subject(:aggregation_result) { described_class.call(invoice:) }

    let(:fees) do
      create_list(:charge_fee, 2, :succeeded, invoice:, amount_cents: 100,
        precise_amount_cents: 100, taxes_amount_cents: 15, taxes_precise_amount_cents: 15)
    end

    before do
      fees.each do |fee|
        create(:fee_applied_tax, fee:, tax: nil, tax_code: "state", tax_name: "State", tax_rate: 10,
          amount_cents: 10, precise_amount_cents: 10)
        create(:fee_applied_tax, fee:, tax: nil, tax_code: "city", tax_name: "City", tax_rate: 5,
          amount_cents: 5, precise_amount_cents: 5)
      end
    end

    it "preserves each jurisdiction while combining its fees" do
      expect(aggregation_result).to be_success
      expect(invoice.applied_taxes.map { |tax| [tax.tax_code, tax.amount_cents] }).to match_array([
        ["state", 20], ["city", 10]
      ])
      expect(invoice.taxes_amount_cents).to eq(30)
    end

    context "when the invoice is credited" do
      subject(:credit_result) { CreditNotes::ComputeTaxesService.call(credit_note:) }

      let(:credit_note) { create(:credit_note, invoice:, customer:) }
      let(:credited_amount) { 100 }
      let(:expected_taxes) { 30 }

      before do
        aggregation_result.raise_if_error!
        invoice.save!
        fees.each do |fee|
          create(:credit_note_item, credit_note:, fee: fee.reload,
            amount_cents: credited_amount, precise_amount_cents: credited_amount)
        end
        credit_note.reload
      end

      it "credits all provider jurisdictions" do
        expect(credit_result).to be_success
        expect(credit_note.taxes_amount_cents).to eq(expected_taxes)
        expect(credit_note.applied_taxes.map(&:tax_code)).to match_array(%w[state city])
      end

      context "with a partial credit" do
        let(:credited_amount) { 50 }
        let(:expected_taxes) { 15 }

        it "prorates both jurisdictions" do
          expect(credit_result).to be_success
          expect(credit_note.applied_taxes.sum(&:amount_cents)).to eq(expected_taxes)
        end
      end
    end
  end
end
