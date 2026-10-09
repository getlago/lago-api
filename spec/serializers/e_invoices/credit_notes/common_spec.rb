# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::CreditNotes::Common do
  {
    ubl: [EInvoices::CreditNotes::Ubl::Builder, "//cac:TaxSubtotal/cbc:TaxAmount", "//cac:TaxTotal/cbc:TaxAmount",
      "//cac:TaxSubtotal/cbc:TaxableAmount"],
    cii: [EInvoices::CreditNotes::Cii::Builder, "//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:CalculatedAmount",
      "//ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount",
      "//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:BasisAmount"]
  }.each do |format, (serializer, subtotal_path, total_path, basis_path)|
    context "with #{format} serialization and multiple native tax rates" do
      subject(:document) { xml_document(format) { |xml| serializer.serialize(xml:, credit_note:) } }

      let(:invoice) { create(:invoice) }
      let(:credit_note) { create(:credit_note, invoice:, customer: invoice.customer) }
      let(:tax10) { create(:tax, organization: invoice.organization, rate: 10) }
      let(:tax20) { create(:tax, organization: invoice.organization, rate: 20) }
      let(:amounts) { [4, 2] }
      let(:coupons) { [0, 0] }
      let(:fee10) do
        create(:fee, invoice:, amount_cents: amounts[0], precise_amount_cents: amounts[0],
          precise_coupons_amount_cents: coupons[0])
      end
      let(:fee20) do
        create(:fee, invoice:, amount_cents: amounts[1], precise_amount_cents: amounts[1],
          precise_coupons_amount_cents: coupons[1])
      end

      before do
        [[fee10, tax10], [fee20, tax20]].each do |fee, tax|
          Fees::ApplyTaxesService.call!(fee:, tax_codes: [tax.code])
          fee.save!
          create(:credit_note_item, credit_note:, fee:,
            amount_cents: fee.amount_cents, precise_amount_cents: fee.precise_amount_cents)
        end
        Invoices::ApplyTaxesService.call!(invoice:)
        invoice.save!
        credit_note.reload
        CreditNotes::ComputeTaxesService.call!(credit_note:)
      end

      it "reconciles fractional tax groups to the booked total without changing their bases" do
        expect(credit_note.precise_taxes_amount_cents).to eq(0.8.to_d)
        expect(credit_note.taxes_amount_cents).to eq(1)
        expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(-0.01.to_d)
        expect(document.at_xpath(total_path).text.to_d).to eq(-0.01.to_d)
        expect(document.xpath(basis_path).map { |node| node.text.to_d }).to match_array([-0.04.to_d, -0.02.to_d])
      end

      context "with coupons deducted before tax" do
        let(:amounts) { [8, 4] }
        let(:coupons) { [4, 2] }

        it "allocates the booked tax using the discounted bases" do
          expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(-0.01.to_d)
          expect(document.at_xpath(total_path).text.to_d).to eq(-0.01.to_d)
          expect(document.xpath(basis_path).map { |node| node.text.to_d }).to match_array([-0.04.to_d, -0.02.to_d])
        end
      end
    end
  end
end
