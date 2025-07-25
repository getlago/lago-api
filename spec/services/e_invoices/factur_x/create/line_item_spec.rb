# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::LineItem, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, line_id:, fee:)
    end
  end

  let(:fee) { create(:fee) }
  let(:line_id) { 1 }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to xml_document_have_comment("Line Item #{line_id}: #{fee.invoice_name}")
    end

    it "have the line id" do
      expect(subject).to xml_document_have_node(
        "//ram:IncludedSupplyChainTradeLineItem/ram:AssociatedDocumentLineDocument/ram:LineID",
        line_id
      )
    end

    it "have the item name" do
      expect(subject).to xml_document_have_node(
        "//ram:IncludedSupplyChainTradeLineItem/ram:SpecifiedTradeProduct/ram:Name",
        fee.item_name
      )
    end

    it "have the item description" do
      expect(subject).to xml_document_have_node(
        "//ram:IncludedSupplyChainTradeLineItem/ram:SpecifiedTradeProduct/ram:Description",
        fee.invoice_name
      )
    end

    it "have the item amount" do
      expect(subject).to xml_document_have_node(
        "//ram:IncludedSupplyChainTradeLineItem/ram:SpecifiedLineTradeAgreement/ram:NetPriceProductTradePrice/ram:ChargeAmount",
        fee.amount
      )
    end

    it "have the item units" do
      expect(subject).to xml_document_have_node(
        "//ram:IncludedSupplyChainTradeLineItem/ram:SpecifiedLineTradeDelivery/ram:BilledQuantity",
        fee.units
      )
    end

    it "have the item taxes rate" do
      expect(subject).to xml_document_have_node(
        "//ram:IncludedSupplyChainTradeLineItem/ram:SpecifiedLineTradeSettlement/ram:ApplicableTradeTax/ram:RateApplicablePercent",
        fee.taxes_rate
      )
    end

    it "have the item total amount" do
      expect(subject).to xml_document_have_node(
        "//ram:IncludedSupplyChainTradeLineItem/ram:SpecifiedLineTradeSettlement/ram:SpecifiedTradeSettlementLineMonetarySummation/ram:LineTotalAmount",
        fee.total_amount
      )
    end
  end
end
