# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::Builder, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice) { create(:invoice) }
  let(:fee) { create(:fee, invoice:) }

  before { fee }

  shared_examples "xml section" do |section|
    it "contains the section tag" do
      expect(subject).to xml_document_have_node(section[:xpath])
    end

    it "contains section name before tag" do
      previous = subject.at_xpath(section[:xpath]).previous

      expect(previous).to be_comment
      expect(previous.text).to match(section[:name])
    end
  end

  describe ".call" do
    it { is_expected.not_to be_nil }

    {
      context: {name: "Exchange Document Context", xpath: "//rsm:CrossIndustryInvoice/rsm:ExchangedDocumentContext"},
      header: {name: "Exchange Document Header", xpath: "//rsm:CrossIndustryInvoice/rsm:ExchangedDocument"},
      trade_transaction: {name: "Supply Chain Trade Transaction", xpath: "//rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction"},
      line_items: {name: /Line Item \d{1,}:.*/, xpath: "//rsm:SupplyChainTradeTransaction/ram:IncludedSupplyChainTradeLineItem"},
      trade_agreement: {name: "Applicable Header Trade Agreement", xpath: "//rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeAgreement"},
      trade_delivery: {name: "Applicable Header Trade Delivery", xpath: "//rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeDelivery"},
      trade_settlement: {name: "Applicable Header Trade Settlement", xpath: "//rsm:SupplyChainTradeTransaction/ram:ApplicableHeaderTradeSettlement"},
      trade_tax: {name: /Tax Information \d{2,3}\.\d{2}% VAT/, xpath: "//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax"},
      trade_allowance_charge: {name: /Allowance\/Charge - Discount \d{2,3}\.\d{2}% portion/, xpath: "//ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeAllowanceCharge"},
      payment_terms: {name: "Payment Terms", xpath: "//ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradePaymentTerms"},
      monetary_summation: {name: "Monetary Summation", xpath: "//ram:ApplicableHeaderTradeSettlement/ram:SpecifiedTradeSettlementHeaderMonetarySummation"}
    }.each do |reference, section|
      it_behaves_like "xml section", section
    end

    context "with Exchange Document Context section" do
      it "have the document schema version number" do
        expect(subject).to xml_document_have_node(
          "//rsm:ExchangedDocumentContext/ram:GuidelineSpecifiedDocumentContextParameter/ram:ID",
          "urn:cen.eu:en16931:2017"
        )
      end
    end
  end
end
