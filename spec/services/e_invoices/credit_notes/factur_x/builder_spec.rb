# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::CreditNotes::FacturX::Builder, type: :service do
  subject do
    xml_document(:factur_x) do |xml|
      described_class.call(xml:, credit_note:)
    end
  end

  let(:credit_note) { create(:credit_note, total_amount_currency: "EUR") }
  let(:credit_note_item) { create(:credit_note_item, credit_note:, fee:) }
  let(:credit_note_item2) { create(:credit_note_item, credit_note:, fee: fee2) }
  let(:fee) { create(:fee, units: 5, amount: 10, precise_unit_amount: 2) }
  let(:fee2) { create(:fee, units: 1, amount: 25, precise_unit_amount: 25) }

  before do
    credit_note_item
    credit_note_item2
  end

  describe ".call" do
    context "when CrossIndustryInvoice tag" do
      it "contains the tag" do
        expect(subject).to contains_xml_node("//rsm:CrossIndustryInvoice")
      end
    end

    context "when ExchangedDocument tag" do
      let(:root) { "//rsm:CrossIndustryInvoice/rsm:ExchangedDocument" }

      it "contains the tag" do
        expect(subject).to contains_xml_node(root)
      end

      context "with credit note info" do
        context "when ID" do
          it "contains the info" do
            expect(subject).to contains_xml_node("#{root}/ram:ID")
              .with_value(credit_note.number)
          end
        end

        context "when TypeCode" do
          it "contains the info" do
            expect(subject).to contains_xml_node("#{root}/ram:TypeCode")
              .with_value(described_class::CREDIT_NOTE)
          end
        end

        context "when IssueDateTime" do
          it "contains the info" do
            expect(subject).to contains_xml_node("#{root}/ram:IssueDateTime/udt:DateTimeString")
              .with_value(credit_note.issuing_date.strftime(described_class::DATEFORMAT))
              .with_attribute("format", described_class::CCYYMMDD)
          end
        end
      end
    end

    context "when SupplyChainTradeTransaction tag" do
      it "contains the tag" do
        expect(subject).to contains_xml_node("//rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction")
      end
    end

    context "when IncludedSupplyChainTradeLineItem tags" do
      it "has all fees" do
        expect(
          subject.xpath(
            "//rsm:CrossIndustryInvoice/rsm:SupplyChainTradeTransaction/ram:IncludedSupplyChainTradeLineItem"
          ).length
        ).to eq(credit_note.fees.count)
      end

      context "with negative values" do
        context "with BilledQuantity" do
          it "is negative" do
            expect(subject).to contains_xml_node(
              "//ram:IncludedSupplyChainTradeLineItem[1]//ram:BilledQuantity"
            ).with_value(-fee.units)
          end
        end

        context "with LineTotalAmount" do
          it "is negative" do
            expect(subject).to contains_xml_node(
              "//ram:IncludedSupplyChainTradeLineItem[1]//ram:LineTotalAmount"
            ).with_value(-fee.amount)
          end
        end
      end
    end

    context "when ApplicableHeaderTradeAgreement tag" do
      it "contains the tag" do
        expect(subject).to contains_xml_node("//ram:ApplicableHeaderTradeAgreement")
      end

      it "contains SpecifiedTaxRegistration tag by default" do
        expect(subject).to contains_xml_node("//ram:ApplicableHeaderTradeAgreement//ram:SpecifiedTaxRegistration/ram:ID")
          .with_value(credit_note.billing_entity.tax_identification_number)
          .with_attribute("schemeID", "VA")
      end
    end

    context "when ApplicableHeaderTradeDelivery tag" do
      it "contains the tag" do
        expect(subject).to contains_xml_node("//ram:ApplicableHeaderTradeDelivery")
      end

      it "contains OccurrenceDateTime" do
        expect(subject).to contains_xml_node("//ram:ActualDeliverySupplyChainEvent/ram:OccurrenceDateTime/udt:DateTimeString")
          .with_value(credit_note.created_at.strftime(described_class::DATEFORMAT))
          .with_attribute("format", described_class::CCYYMMDD)
      end
    end

    context "when ApplicableHeaderTradeSettlement tag" do
      it "contains the tag" do
        expect(subject).to contains_xml_node("//ram:ApplicableHeaderTradeSettlement")
      end

      it "contains InvoiceCurrencyCode" do
        expect(subject).to contains_xml_node("//ram:ApplicableHeaderTradeSettlement/ram:InvoiceCurrencyCode")
          .with_value(credit_note.currency)
      end
    end
  end
end
