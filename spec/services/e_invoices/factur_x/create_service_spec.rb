# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::CreateService, type: :service do
  let(:invoice) { create(:invoice) }
  let(:xml_builder_double) { instance_double(Nokogiri::XML::Builder, to_xml: "<xml>content</xml>") }

  describe "#call" do
    it "builds the XML and writes it to a file" do
      # rubocop:disable RSpec/MessageSpies
      expect(Nokogiri::XML::Builder).to receive(:new).with(encoding: "UTF-8")
        .and_yield(xml_builder_double).and_return(xml_builder_double)

      expect(EInvoices::FacturX::Create::Builder).to receive(:call)
        .with(xml: xml_builder_double, invoice:)

      expect(File).to receive(:write).with("output.xml", "<xml>content</xml>")

      described_class.new(invoice:).call
      # rubocop:enable RSpec/MessageSpies
    end
  end
end
