# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::Create::Context, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:)
    end
  end

  let(:context_version) { "urn:cen.eu:en16931:2017" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to xml_document_have_comment("Exchange Document Context")
    end

    it "have the document schema version number" do
      expect(subject).to xml_document_have_node(
        "//rsm:ExchangedDocumentContext/ram:GuidelineSpecifiedDocumentContextParameter/ram:ID",
        context_version
      )
    end
  end
end
