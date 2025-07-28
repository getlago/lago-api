# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::Builder, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice_subscription) { create(:invoice_subscription, :boundaries, invoice:, subscription: subscription) }
  let(:subscription) { create(:subscription, started_at: "2025-03-16".to_date) }
  let(:invoice) { create(:invoice, total_amount_cents: 30_00, currency: "USD") }
  let(:fee) { create(:fee, invoice:) }

  before do
    fee
    invoice_subscription
  end

  shared_examples "xml section" do |section|
    it "contains the section tag" do
      expect(subject).to contains_xml_node(section[:xpath])
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
        expect(subject).to contains_xml_node(
          "//rsm:ExchangedDocumentContext/ram:GuidelineSpecifiedDocumentContextParameter/ram:ID"
        ).with_value("urn:cen.eu:en16931:2017")
      end
    end

    context "when payments tags" do
      context "when something to pay" do
        it_behaves_like "xml section", {name: "Payment Means: Standard payment", xpath: "(//ram:SpecifiedTradeSettlementPaymentMeans)[1]"}
      end

      context "with prepaid and credit note" do
        before do
          invoice.update(
            credit_notes_amount_cents: 10_00,
            prepaid_credit_amount_cents: 10_00
          )
        end

        it_behaves_like "xml section", {name: "Payment Means: Standard payment", xpath: "(//ram:SpecifiedTradeSettlementPaymentMeans)[1]"}
        it_behaves_like "xml section", {name: "Payment Means: Prepaid credit", xpath: "(//ram:SpecifiedTradeSettlementPaymentMeans)[2]"}
        it_behaves_like "xml section", {name: "Payment Means: Credit note", xpath: "(//ram:SpecifiedTradeSettlementPaymentMeans)[3]"}
      end

      context "when nothing else to pay" do
        before do
          invoice.update(
            total_paid_amount_cents: invoice.total_due_amount_cents,
            credit_notes_amount_cents: invoice.total_due_amount_cents
          )
        end

        it_behaves_like "xml section", {name: "Payment Means: Credit note", xpath: "(//ram:SpecifiedTradeSettlementPaymentMeans)[1]"}
      end
    end
  end
end
