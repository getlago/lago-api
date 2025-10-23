# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Header do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.serialize(xml:, resource:, type_code:, notes:)
    end
  end

  let(:invoice) { create(:invoice, issuing_date: issuing_date.to_date) }
  let(:resource) { invoice }
  let(:type_code) { described_class::COMMERCIAL_INVOICE }
  let(:notes) { ["Invoice ID: #{invoice.id}", "Allow multiple notes"] }
  let(:issuing_date) { "20250316" }

  let(:root) { "//rsm:ExchangedDocument" }

  before { invoice }

  describe ".serialize" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Exchange Document Header")
    end

    context "when invoice" do
      it "expects to have the invoice number" do
        expect(subject).to contains_xml_node("#{root}/ram:ID").with_value(invoice.number)
      end

      it "expects to have a type code" do
        expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(described_class::COMMERCIAL_INVOICE)
      end

      it "expects to have invoice issuing date" do
        expect(subject).to contains_xml_node("#{root}/ram:IssueDateTime/udt:DateTimeString")
          .with_value(issuing_date)
          .with_attribute("format", described_class::CCYYMMDD)
      end

      context "with notes" do
        it "expects to have first included note" do
          expect(subject).to contains_xml_node("#{root}/ram:IncludedNote[1]/ram:Content")
            .with_value("Invoice ID: #{invoice.id}")
        end

        it "expects to have last included notes" do
          expect(subject).to contains_xml_node("#{root}/ram:IncludedNote[2]/ram:Content")
            .with_value("Allow multiple notes")
        end
      end
    end

    context "when credit note" do
      let(:credit_note) { create(:credit_note, invoice:, issuing_date: issuing_date.to_date) }
      let(:issuing_date) { "20250317" }
      let(:resource) { credit_note }
      let(:type_code) { described_class::CREDIT_NOTE }

      it "expects to have the credit note number" do
        expect(subject).to contains_xml_node("#{root}/ram:ID").with_value(credit_note.number)
      end

      it "expects to have a type code" do
        expect(subject).to contains_xml_node("#{root}/ram:TypeCode").with_value(described_class::CREDIT_NOTE)
      end

      it "expects to have invoice issuing date" do
        expect(subject).to contains_xml_node("#{root}/ram:IssueDateTime/udt:DateTimeString")
          .with_value(issuing_date)
          .with_attribute("format", described_class::CCYYMMDD)
      end
    end
  end
end
