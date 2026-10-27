# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CreditNotes::EstimateSerializer do
  subject(:payload) { described_class.new(credit_note, root_name: "estimated_credit_note", includes:).serialize }

  let(:includes) { %i[items applied_taxes] }
  let(:credit_note) { build(:credit_note, total_amount_cents: 3000, taxes_amount_cents: 500, credit_amount_cents: 3000, refund_amount_cents: 0) }
  let(:item) { build(:credit_note_item, credit_note:, amount_cents: 2500, precise_amount_cents: 2500) }
  let(:tax) { build(:credit_note_applied_tax, credit_note:, tax_rate: 20, base_amount_cents: 2500, amount_cents: 500) }

  before do
    credit_note.items << item
    credit_note.applied_taxes << tax
  end

  it "serializes the selected amounts without persisted tax metadata or coupon adjustments" do
    expect(payload).to eq(
      lago_invoice_id: credit_note.invoice_id,
      invoice_number: credit_note.invoice.number,
      currency: credit_note.currency,
      sub_total_excluding_taxes_amount_cents: 2500,
      taxes_amount_cents: 500,
      sub_total_including_taxes_amount_cents: 3000,
      total_amount_cents: 3000,
      max_creditable_amount_cents: 3000,
      max_refundable_amount_cents: 0,
      items: [{lago_fee_id: item.fee_id, amount_cents: 2500}],
      applied_taxes: [{
        lago_tax_id: tax.tax_id,
        tax_name: tax.tax_name,
        tax_code: tax.tax_code,
        tax_rate: tax.tax_rate,
        tax_description: tax.tax_description,
        base_amount_cents: 2500,
        amount_cents: 500,
        currency: "EUR"
      }]
    )
  end

  context "when the taxable base is smaller than the credited fee amount" do
    let(:tax) { build(:credit_note_applied_tax, credit_note:, tax_rate: 20, base_amount_cents: 2000, amount_cents: 400) }

    it "retains the tax base rather than renaming it as the fee subtotal" do
      expect(payload[:applied_taxes].sole).to eq(
        lago_tax_id: tax.tax_id,
        tax_name: tax.tax_name,
        tax_code: tax.tax_code,
        tax_rate: 20,
        tax_description: tax.tax_description,
        base_amount_cents: 2000,
        amount_cents: 400,
        currency: "EUR"
      )
    end
  end

  context "when selected items have different tax rates" do
    let(:second_tax) { build(:credit_note_applied_tax, credit_note:, tax_rate: 10, base_amount_cents: 1000, amount_cents: 100) }

    before { credit_note.applied_taxes << second_tax }

    it "keeps each tax rate on its own row without an aggregate rate" do
      expect(payload[:applied_taxes]).to eq([
        {
          lago_tax_id: tax.tax_id,
          tax_name: tax.tax_name,
          tax_code: tax.tax_code,
          tax_rate: tax.tax_rate,
          tax_description: tax.tax_description,
          base_amount_cents: 2500,
          amount_cents: 500,
          currency: "EUR"
        },
        {
          lago_tax_id: second_tax.tax_id,
          tax_name: second_tax.tax_name,
          tax_code: second_tax.tax_code,
          tax_rate: second_tax.tax_rate,
          tax_description: second_tax.tax_description,
          base_amount_cents: 1000,
          amount_cents: 100,
          currency: "EUR"
        }
      ])
    end
  end

  context "without expansions" do
    let(:includes) { [] }

    it "keeps relationships out of the base payload" do
      expect(payload).not_to have_key(:items)
      expect(payload).not_to have_key(:applied_taxes)
    end
  end
end
