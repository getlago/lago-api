# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::LineItem, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, line_id:, fee:)
    end
  end

  let(:fee) { create(:fee, precise_unit_amount: 0.059) }
  let(:line_id) { 1 }

  let(:root) { "//ram:IncludedSupplyChainTradeLineItem" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Line Item #{line_id}: #{fee.invoice_name}")
    end

    it "have the line id" do
      expect(subject).to contains_xml_node("#{root}/ram:AssociatedDocumentLineDocument/ram:LineID")
        .with_value(line_id)
    end

    it "have the item name" do
      expect(subject).to contains_xml_node("#{root}/ram:SpecifiedTradeProduct/ram:Name").with_value(fee.item_name)
    end

    it "have the item description" do
      expect(subject).to contains_xml_node("#{root}/ram:SpecifiedTradeProduct/ram:Description").with_value(fee.invoice_name)
    end

    it "have the item unit amount" do
      expect(subject).to contains_xml_node(
        "#{root}/ram:SpecifiedLineTradeAgreement/ram:NetPriceProductTradePrice/ram:ChargeAmount"
      ).with_value("0.059")
    end

    context "with BilledQuantity" do
      let(:xpath) { "#{root}/ram:SpecifiedLineTradeDelivery/ram:BilledQuantity" }

      it "have the item units" do
        expect(subject).to contains_xml_node(xpath)
          .with_value(fee.units)
          .with_attribute("unitCode", "C62")
      end
    end

    it "have the item taxes rate" do
      expect(subject).to contains_xml_node(
        "#{root}/ram:SpecifiedLineTradeSettlement/ram:ApplicableTradeTax/ram:RateApplicablePercent"
      ).with_value(fee.taxes_rate)
    end

    it "have the item total amount" do
      expect(subject).to contains_xml_node(
        "#{root}/ram:SpecifiedLineTradeSettlement/ram:SpecifiedTradeSettlementLineMonetarySummation/ram:LineTotalAmount"
      ).with_value(fee.amount)
    end
  end
end
