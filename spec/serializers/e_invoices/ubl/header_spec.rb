# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Header do
  subject do
    xml_document(:ubl) do |xml|
      described_class.serialize(xml:, resource:, type_code:)
    end
  end

  let(:resource) { create(:invoice, issuing_date: issuing_date.to_date, currency:) }
  let(:issuing_date) { "2025-03-16" }
  let(:currency) { "USD" }
  let(:type_code) { described_class::COMMERCIAL_INVOICE }

  before { resource }

  describe ".serialize" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Invoice Header Information")
    end

    it "expects to have the resource number" do
      expect(subject).to contains_xml_node("//cbc:ID").with_value(resource.number)
    end

    it "expects to have resource issuing date" do
      expect(subject).to contains_xml_node("//cbc:IssueDate").with_value(issuing_date)
    end

    context "with type_codes" do
      [
        described_class::COMMERCIAL_INVOICE,
        described_class::PREPAID_INVOICE,
        described_class::SELF_BILLED_INVOICE
      ].each do |invoice_type|
        context "when Invoice #{invoice_type}" do
          let(:type_code) { invoice_type }

          it "expects to have a type code" do
            expect(subject).to contains_xml_node("//cbc:InvoiceTypeCode").with_value(invoice_type)
          end
        end
      end

      [
        described_class::CREDIT_NOTE
      ].each do |credit_note_type|
        context "when Credit Note #{credit_note_type}" do
          let(:type_code) { credit_note_type }

          it "expects to have a type code" do
            expect(subject).to contains_xml_node("//cbc:CreditNoteTypeCode").with_value(credit_note_type)
          end
        end
      end
    end

    it "expects to have resource currency" do
      expect(subject).to contains_xml_node("//cbc:DocumentCurrencyCode")
        .with_value(resource.currency)
    end
  end
end
