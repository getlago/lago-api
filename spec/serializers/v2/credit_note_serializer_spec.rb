# frozen_string_literal: true

require "rails_helper"

RSpec.describe V2::CreditNoteSerializer do
  subject(:payload) { described_class.new(credit_note, includes:).serialize }

  let(:credit_note) { create(:credit_note, total_amount_cents: 3000, taxes_amount_cents: 500) }
  let(:item) { create(:credit_note_item, credit_note:, amount_cents: 2500, precise_amount_cents: 2500) }
  let(:tax) { create(:credit_note_applied_tax, credit_note:, base_amount_cents: 2500, amount_cents: 500) }
  let(:includes) { %i[usec_timestamps] }

  before do
    item
    tax
    credit_note.items.reset
    credit_note.applied_taxes.reset
  end

  it "serializes a persisted note without embedding relationships by default" do
    expect(payload).to eq(
      lago_id: credit_note.id,
      billing_entity_code: credit_note.invoice.billing_entity.code,
      sequential_id: credit_note.sequential_id,
      number: credit_note.number,
      lago_invoice_id: credit_note.invoice_id,
      invoice_number: credit_note.invoice.number,
      purchase_order_number: credit_note.purchase_order_number,
      issuing_date: credit_note.issuing_date.iso8601,
      credit_status: credit_note.credit_status,
      refund_status: credit_note.refund_status,
      reason: credit_note.reason,
      description: credit_note.description,
      currency: credit_note.currency,
      sub_total_excluding_taxes_amount_cents: 2500,
      taxes_amount_cents: 500,
      sub_total_including_taxes_amount_cents: 3000,
      total_amount_cents: 3000,
      balance_amount_cents: credit_note.balance_amount_cents,
      credit_amount_cents: credit_note.credit_amount_cents,
      refund_amount_cents: credit_note.refund_amount_cents,
      offset_amount_cents: credit_note.offset_amount_cents,
      created_at: credit_note.created_at.iso8601(6),
      updated_at: credit_note.updated_at.iso8601(6),
      file_url: nil,
      xml_url: nil,
      self_billed: credit_note.invoice.self_billed
    )
  end

  context "with expanded tax and item details" do
    let(:includes) { %i[items applied_taxes usec_timestamps] }

    it "uses the same selected-fee and tax fields as the estimate" do
      expect(payload.except(:items, :applied_taxes)).to eq(described_class.new(credit_note, includes: %i[usec_timestamps]).serialize)
      expect(payload[:items]).to eq([{lago_fee_id: item.fee_id, amount_cents: 2500}])
      expect(payload[:applied_taxes]).to eq([{
        lago_tax_id: tax.tax_id,
        tax_name: tax.tax_name,
        tax_code: tax.tax_code,
        tax_rate: tax.tax_rate,
        tax_description: tax.tax_description,
        base_amount_cents: 2500,
        amount_cents: 500,
        currency: "EUR"
      }])
    end
  end
end
