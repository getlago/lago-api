# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreditNotes::ApplyTaxesService, type: :service do
  subject(:apply_service) { described_class.new(invoice:, items:) }

  let(:customer) { create(:customer) }
  let(:organization) { customer.organization }

  let(:invoice) do
    create(
      :invoice,
      customer:,
      organization:,
      currency: 'EUR',
      fees_amount_cents: 120,
      coupons_amount_cents: 20,
      taxes_amount_cents: 20,
      total_amount_cents: 120,
      payment_status: :succeeded,
      taxes_rate: 20,
      version_number: 3
    )
  end

  let(:fee1) do
    create(
      :fee,
      invoice:,
      amount_cents: 100,
      taxes_amount_cents: 12,
      taxes_rate: 12,
      precise_coupons_amount_cents: (20 * 100).fdiv(120)
    )
  end

  let(:fee2) do
    create(
      :fee,
      invoice:,
      amount_cents: 20,
      taxes_amount_cents: 4,
      taxes_rate: 20,
      precise_coupons_amount_cents: (20 * 20).fdiv(120)
    )
  end

  let(:tax1) { create(:tax, organization:, rate: 12) }
  let(:tax2) { create(:tax, organization:, rate: 8) }

  let(:fee_applied_tax11) do
    create(
      :fee_applied_tax,
      tax: tax1,
      tax_code: tax1.code,
      fee: fee1,
      amount_cents: (fee1.sub_total_excluding_taxes_amount_cents * tax1.rate).fdiv(100)
    )
  end

  let(:fee_applied_tax21) do
    create(
      :fee_applied_tax,
      tax: tax1,
      tax_code: tax1.code,
      fee: fee2,
      amount_cents: (fee2.sub_total_excluding_taxes_amount_cents * tax1.rate).fdiv(100)
    )
  end

  let(:fee_applied_tax22) do
    create(
      :fee_applied_tax,
      tax: tax2,
      tax_code: tax2.code,
      fee: fee2,
      amount_cents: (fee2.sub_total_excluding_taxes_amount_cents * tax2.rate).fdiv(100)
    )
  end

  let(:invoice_applied_taxes) {
    [
      create(:invoice_applied_tax, tax_code: tax1.code, tax_rate: tax1.rate, tax: tax1, invoice:),
      create(:invoice_applied_tax, tax_code: tax2.code, tax_rate: tax2.rate, tax: tax2, invoice:)
    ]
  }

  let(:items) do
    [
      build(
        :credit_note_item,
        credit_note: nil,
        fee: fee1,
        amount_cents: 20,
        precise_amount_cents: 20,
        amount_currency: invoice.currency
      ),
      build(
        :credit_note_item,
        credit_note: nil,
        fee: fee2,
        amount_cents: 50,
        precise_amount_cents: 50,
        amount_currency: invoice.currency
      )
    ]
  end

  before do
    invoice_applied_taxes
    fee_applied_tax11
    fee_applied_tax21
    fee_applied_tax22
  end

  describe 'call' do
    it 'creates applied taxes' do
      result = apply_service.call

      aggregate_failures do
        expect(result).to be_success

        aggregate_failures do
          applied_taxes = result.applied_taxes
          expect(applied_taxes.count).to eq(2)

          expect(applied_taxes[0]).to have_attributes(
            credit_note: nil,
            tax: tax1,
            tax_description: tax1.description,
            tax_code: tax1.code,
            tax_name: tax1.name,
            tax_rate: 12,
            amount_currency: invoice.currency,
            amount_cents: 7
          )

          expect(applied_taxes[1]).to have_attributes(
            credit_note: nil,
            tax: tax2,
            tax_description: tax2.description,
            tax_code: tax2.code,
            tax_name: tax2.name,
            tax_rate: 8,
            amount_currency: invoice.currency,
            amount_cents: 3
          )

          expect(result.taxes_amount_cents.round).to eq(10)
          expect(result.taxes_rate).to eq(17.71429)
          expect(result.coupons_adjustment_amount_cents.round).to eq(12)
        end
      end
    end
  end
end
