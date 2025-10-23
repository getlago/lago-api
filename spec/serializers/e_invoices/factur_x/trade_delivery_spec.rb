# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::FacturX::TradeDelivery do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, delivery_date:)
    end
  end

  let(:delivery_date) { "20250316".to_date }

  let(:root) { "//ram:ApplicableHeaderTradeDelivery" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Applicable Header Trade Delivery")
    end

    context "when OccurrenceDateTime" do
      let(:xpath) { "#{root}/ram:ActualDeliverySupplyChainEvent/ram:OccurrenceDateTime/udt:DateTimeString" }

      it "have the delivery date" do
        expect(subject).to contains_xml_node(xpath).with_value("20250316").with_attribute("format", 102)
      end
    end
  end
end
