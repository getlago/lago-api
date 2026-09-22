# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::CreateService, :premium do
  subject(:create_credit_note) { described_class.call!(invoice:, items:, credit_amount_cents:, refund_amount_cents:).credit_note }

  let(:estimate) { CreditNotes::EstimateService.call!(invoice:, items:).credit_note }
  let(:credit_amount_cents) { 206 }
  let(:refund_amount_cents) { 0 }
  let(:invoice) { create(:invoice, invoice_type: :one_off, version_number: 3, payment_status: :succeeded) }
  let(:fees) { create_list(:fee, 2, invoice:, amount_cents: 100, precise_amount_cents: 100) }
  let(:items) { fees.map { |fee| {fee_id: fee.id, amount_cents: 100} } }
  let(:provider_taxes) do
    fees.map do |fee|
      build(:tax_result, item_id: fee.id, tax_amount_cents: 3, tax_breakdown: [
        build(:tax_breakdown_item, name: "Sales tax", type: "tax", rate: "0.025", tax_amount: 3)
      ])
    end
  end

  before do
    create(:anrok_customer, customer: invoice.customer)
    Invoices::ComputeAmountsFromFees.call!(invoice:, provider_taxes:)
    invoice.total_paid_amount_cents = invoice.total_amount_cents
    invoice.save!
  end

  it "estimates a full credit and refund of the booked tax" do
    expect(estimate).to have_attributes(taxes_amount_cents: 6, credit_amount_cents: 206, refund_amount_cents: 206)
    expect(estimate.applied_taxes.sum(&:amount_cents)).to eq(6)
    expect(invoice.creditable_amount_cents).to eq(206)
  end

  it "creates a full credit with the booked tax" do
    credit_note = create_credit_note

    expect(credit_note).to have_attributes(taxes_amount_cents: 6, total_amount_cents: 206)
    expect(invoice.reload.creditable_amount_cents).to eq(0)
  end

  context "when the current customer no longer has a tax provider" do
    before { allow(invoice.customer).to receive(:tax_customer).and_return(nil) }

    it "uses the recorded taxes rather than the current integration" do
      expect(estimate.taxes_amount_cents).to eq(6)
    end
  end

  context "when provider rounding differs from recalculated tax by more than one cent" do
    let(:fees) { create_list(:fee, 4, invoice:, amount_cents: 100, precise_amount_cents: 100) }
    let(:credit_amount_cents) { 0 }
    let(:refund_amount_cents) { 412 }

    it "allows refunding the entire amount paid" do
      credit_note = create_credit_note

      expect(credit_note).to have_attributes(taxes_amount_cents: 12, refund_amount_cents: 412, total_amount_cents: 412)
      expect(invoice.reload.refundable_amount_cents).to eq(0)
    end
  end

  context "when every prorated jurisdiction tax rounds down" do
    let(:items) { [{fee_id: fees.first.id, amount_cents: 20}] }
    let(:provider_taxes) do
      fees.map do |fee|
        build(:tax_result, item_id: fee.id, tax_amount_cents: 3, tax_breakdown: %w[state county city].map do |name|
          build(:tax_breakdown_item, name:, type: "tax", rate: "0.01", tax_amount: 1)
        end)
      end
    end

    it "allocates the rounded credit total without losing all jurisdiction amounts" do
      expect(estimate.taxes_amount_cents).to eq(1)
      expect(estimate.applied_taxes.sum(&:amount_cents)).to eq(1)
    end
  end

  context "when a first partial credit has rounded up" do
    let(:credit_amount_cents) { 154 }
    let(:items) { [{fee_id: fees.first.id, amount_cents: 50}, {fee_id: fees.last.id, amount_cents: 100}] }
    let(:previous_credit) do
      described_class.call!(invoice:, items: [{fee_id: fees.first.id, amount_cents: 50}], credit_amount_cents: 52).credit_note
    end

    before { previous_credit }

    it "refunds only the remaining cents and reconciles the tax lines" do
      expect(previous_credit.taxes_amount_cents).to eq(2)
      expect(estimate).to have_attributes(taxes_amount_cents: 4, credit_amount_cents: 154, refund_amount_cents: 154)
      expect(estimate.applied_taxes.sum(&:amount_cents)).to eq(4)
    end

    it "creates the final credit without losing or refunding an extra cent" do
      credit_note = create_credit_note

      expect(credit_note).to have_attributes(taxes_amount_cents: 4, total_amount_cents: 154)
      expect(credit_note.applied_taxes.sum(&:amount_cents)).to eq(4)
      expect(invoice.reload.credit_notes.sum(:total_amount_cents)).to eq(206)
    end
  end

  {
    ubl: [EInvoices::CreditNotes::Ubl::Builder, "//cac:TaxSubtotal/cbc:TaxAmount", "//cac:TaxTotal/cbc:TaxAmount"],
    cii: [EInvoices::CreditNotes::Cii::Builder, "//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:CalculatedAmount",
      "//ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount"]
  }.each do |format, (serializer, subtotal_path, total_path)|
    context "with #{format} serialization" do
      subject(:document) { xml_document(format) { |xml| serializer.serialize(xml:, credit_note:) } }

      let(:credit_amount_cents) { 206 }
      let(:expected_tax) { -0.06.to_d }
      let(:credit_note) { described_class.call!(invoice:, items:, credit_amount_cents:).credit_note }

      it "exports the tax that was actually credited" do
        expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(expected_tax)
        expect(document.at_xpath(total_path).text.to_d).to eq(expected_tax)
      end

      context "when an earlier credit covered part of the same fee" do
        let(:credit_amount_cents) { 154 }
        let(:expected_tax) { -0.04.to_d }
        let(:items) { [{fee_id: fees.first.id, amount_cents: 50}, {fee_id: fees.last.id, amount_cents: 100}] }

        before do
          described_class.call!(invoice:, items: [{fee_id: fees.first.id, amount_cents: 50}], credit_amount_cents: 52)
        end

        it "exports only this credit note's base and its remaining tax" do
          basis_path = (format == :ubl) ? "//cac:TaxSubtotal/cbc:TaxableAmount" : "//ram:ApplicableTradeTax/ram:BasisAmount"

          expect(document.at_xpath(basis_path).text.to_d).to eq(-1.50.to_d)
          expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(expected_tax)
          expect(document.at_xpath(total_path).text.to_d).to eq(expected_tax)
        end
      end
    end
  end
end
