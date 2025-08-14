# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::Builder, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice_subscription) { create(:invoice_subscription, :boundaries, invoice:, subscription: subscription) }
  let(:subscription) { create(:subscription, started_at: "2025-03-16".to_date) }
  let(:invoice) { create(:invoice, total_amount_cents: 30_00, currency: "USD", coupons_amount_cents: 1000) }
  let(:fee) { create(:fee, invoice:, amount_cents: 10000, taxes_rate: 20.00) }
  let(:invoice_applied_tax) { create(:invoice_applied_tax, invoice:, tax_rate: 20.00) }

  before do
    fee
    invoice_subscription
    invoice_applied_tax
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

  payment_tag = "//cac:PaymentMeans"

  describe ".call" do
    it { is_expected.not_to be_nil }

    {
      ubl_info: {name: "UBL Version and Customization", xpath: "//cbc:UBLVersionID"},
      invoice_header: {name: "Invoice Header Information", xpath: "//cbc:ID"},
      invoice_seller: {name: "Supplier Party", xpath: "//cac:AccountingSupplierParty"},
      invoice_customer: {name: "Customer Party", xpath: "//cac:AccountingCustomerParty"},
      delivery: {name: "Delivery Information", xpath: "//cac:Delivery"},
      payment_and_credits: {name: "Payment Means:", xpath: "//cac:PaymentMeans"},
      payment_terms: {name: "Payment Terms", xpath: "//cac:PaymentTerms"}
    }.each do |reference, section|
      it_behaves_like "xml section", section
    end

    context "with Version and Customization" do
      it "have the document info" do
        expect(subject).to contains_xml_node("//cbc:UBLVersionID").with_value(2.1)
        expect(subject).to contains_xml_node("//cbc:CustomizationID").with_value("urn:cen.eu:en16931:2017")
      end
    end

    context "when payments and credits" do
      context "when something to pay" do
        it_behaves_like "xml section", {name: "Payment Means: Standard payment", xpath: "(#{payment_tag})[1]"}
      end

      context "with prepaid and credit note" do
        before do
          invoice.update(
            credit_notes_amount_cents: 10_00,
            prepaid_credit_amount_cents: 10_00
          )
        end

        it_behaves_like "xml section", {name: "Payment Means: Standard payment", xpath: "(#{payment_tag})[1]"}
        it_behaves_like "xml section", {name: "Payment Means: Prepaid credit", xpath: "(#{payment_tag})[2]"}
        it_behaves_like "xml section", {name: "Payment Means: Credit note", xpath: "(#{payment_tag})[3]"}
      end

      context "when nothing else to pay" do
        before do
          invoice.update(
            total_paid_amount_cents: invoice.total_due_amount_cents,
            credit_notes_amount_cents: invoice.total_due_amount_cents
          )
        end

        it_behaves_like "xml section", {name: "Payment Means: Credit note", xpath: "(#{payment_tag})[1]"}
      end
    end
  end
end
