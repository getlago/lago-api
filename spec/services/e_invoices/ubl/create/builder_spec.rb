# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::Builder, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, invoice:)
    end
  end

  let(:invoice) { create(:invoice) }

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
      ubl_header: {name: "UBL Version and Customization", xpath: "//cbc:UBLVersionID"}
    }.each do |reference, section|
      it_behaves_like "xml section", section
    end

    context "with Version and Customization" do
      it "have the document info" do
        expect(subject).to contains_xml_node("//cbc:UBLVersionID").with_value(2.1)
        expect(subject).to contains_xml_node("//cbc:CustomizationID").with_value("urn:cen.eu:en16931:2017")
      end
    end
  end
end
