# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Header, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, resource:, type_code:)
    end
  end

  let(:resource) { create(:invoice, issuing_date: issuing_date.to_date, currency:) }
  let(:issuing_date) { "2025-03-16" }
  let(:currency) { "USD" }
  let(:type_code) { EInvoices::BaseService::COMMERCIAL_INVOICE }

  before { resource }

  describe ".call" do
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

    it "expects to have a type code" do
      expect(subject).to contains_xml_node("//cbc:InvoiceTypeCode").with_value(type_code)
    end

    it "expects to have resource currency" do
      expect(subject).to contains_xml_node("//cbc:DocumentCurrencyCode")
        .with_value(resource.currency)
    end
  end
end
