# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Invoices::Common do
  {
    ubl: [EInvoices::Invoices::Ubl::Builder, "//cac:TaxSubtotal/cbc:TaxAmount", "//cac:TaxTotal/cbc:TaxAmount"],
    cii: [EInvoices::Invoices::Cii::Builder, "//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:CalculatedAmount",
      "//ram:SpecifiedTradeSettlementHeaderMonetarySummation/ram:TaxTotalAmount"]
  }.each do |format, (serializer, subtotal_path, total_path)|
    context "with #{format} serialization" do
      subject(:document) { xml_document(format) { |xml| serializer.serialize(xml:, invoice:) } }

      let(:invoice) { create(:invoice, invoice_type: :one_off) }
      let(:fee) { create(:fee, invoice:, amount_cents: 1000, precise_amount_cents: 1000) }
      let(:expected_tax_cents) { 146 }
      let(:provider_taxes) do
        [build(:tax_result, item_id: fee.id, tax_amount_cents: 146, tax_breakdown: [
          build(:tax_breakdown_item, name: "State tax", type: "tax", rate: "0.12", tax_amount: 96),
          build(:tax_breakdown_item, name: "City tax", type: "tax", rate: "0.05", tax_amount: 50)
        ])]
      end

      before do
        create(:anrok_customer, customer: invoice.customer)
        Invoices::ComputeAmountsFromFees.call!(invoice:, provider_taxes:)
      end

      it "reports tax subtotals equal to the invoice tax total" do
        expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(expected_tax_cents / 100.to_d)
        expect(document.at_xpath(total_path).text.to_d).to eq(expected_tax_cents / 100.to_d)
        expect(invoice.taxes_amount_cents).to eq(expected_tax_cents)
      end

      context "when the provider rounds the tax up" do
        let(:fee) { create(:fee, invoice:, amount_cents: 6, precise_amount_cents: 6) }
        let(:provider_taxes) do
          [build(:tax_result, item_id: fee.id, tax_amount_cents: 1, tax_breakdown: [
            build(:tax_breakdown_item, name: "VAT", type: "tax", rate: "0.10", tax_amount: 1)
          ])]
        end
        let(:basis_path) do
          (format == :ubl) ? "//cac:TaxSubtotal/cbc:TaxableAmount" : "//ram:ApplicableTradeTax/ram:BasisAmount"
        end

        it "keeps the taxable base within the actual fee amount" do
          expect(document.at_xpath(basis_path).text.to_d).to eq(0.06.to_d)
          expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(0.01.to_d)
        end
      end

      context "when independent fees round up at the same tax rate" do
        let(:fee) { create(:fee, invoice:, amount_cents: 100, precise_amount_cents: 100) }
        let(:other_fee) { create(:fee, invoice:, amount_cents: 100, precise_amount_cents: 100) }
        let(:provider_taxes) do
          [fee, other_fee].map do |item|
            build(:tax_result, item_id: item.id, tax_amount_cents: 3, tax_breakdown: [
              build(:tax_breakdown_item, name: "Sales tax", type: "tax", rate: "0.025", tax_amount: 2.5.to_d)
            ])
          end
        end

        it "exports the booked total instead of rounding the precise sum" do
          expect(invoice.fees.sum(:taxes_precise_amount_cents)).to eq(5.to_d)
          expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(0.06.to_d)
          expect(document.at_xpath(total_path).text.to_d).to eq(0.06.to_d)
        end
      end
    end

    context "with #{format} serialization and invoice-level rounding" do
      subject(:document) { xml_document(format) { |xml| serializer.serialize(xml:, invoice:) } }

      let(:invoice) { create(:invoice, invoice_type: :one_off, taxes_amount_cents: 1) }

      before do
        create_list(:fee, 2, invoice:, amount_cents: 4, precise_amount_cents: 4,
          taxes_rate: 10, taxes_amount_cents: 0, taxes_precise_amount_cents: 0.4.to_d)
      end

      it "exports the invoice tax even when each fee rounds down to zero" do
        expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(0.01.to_d)
        expect(document.at_xpath(total_path).text.to_d).to eq(0.01.to_d)
      end

      context "when a legacy provider invoice has zero booked tax on each fee" do
        before do
          create(:invoice_applied_tax, invoice:, tax: nil, tax_rate: 10, fees_amount_cents: 8,
            taxable_base_amount_cents: 8, amount_cents: 1)
        end

        it "retains the invoice tax in the XML subtotals" do
          expect(document.xpath(subtotal_path).sum { |node| node.text.to_d }).to eq(0.01.to_d)
          expect(document.at_xpath(total_path).text.to_d).to eq(0.01.to_d)
        end
      end
    end

    context "with #{format} serialization and multiple native tax rates" do
      subject(:document) { xml_document(format) { |xml| serializer.serialize(xml:, invoice:) } }

      let(:invoice) { create(:invoice, invoice_type: :one_off) }
      let(:tax10) { create(:tax, organization: invoice.organization, rate: 10) }
      let(:tax20) { create(:tax, organization: invoice.organization, rate: 20) }
      let(:small_fees) { create_list(:fee, 2, invoice:, amount_cents: 3, precise_amount_cents: 3) }
      let(:large_fee) { create(:fee, invoice:, amount_cents: 100, precise_amount_cents: 100) }

      before do
        small_fees.each do |fee|
          Fees::ApplyTaxesService.call!(fee:, tax_codes: [tax10.code])
          fee.save!
        end
        Fees::ApplyTaxesService.call!(fee: large_fee, tax_codes: [tax20.code])
        large_fee.save!
        Invoices::ApplyTaxesService.call!(invoice:)
      end

      it "keeps the rounding cent in its original tax-rate subtotal" do
        expect(invoice.taxes_amount_cents).to eq(21)
        rate_path = if format == :ubl
          "//cac:TaxSubtotal[cac:TaxCategory/cbc:Percent='10.00']/cbc:TaxAmount"
        else
          "//ram:ApplicableTradeTax[ram:RateApplicablePercent='10.00']/ram:CalculatedAmount"
        end
        expect(document.at_xpath(rate_path).text.to_d).to eq(0.01.to_d)
        expect(document.xpath(subtotal_path).map { |node| node.text.to_d }).to match_array([0.01.to_d, 0.20.to_d])
        expect(document.at_xpath(total_path).text.to_d).to eq(0.21.to_d)
      end
    end
  end
end
