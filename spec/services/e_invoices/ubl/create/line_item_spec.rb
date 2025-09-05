# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoices::Ubl::Create::LineItem, type: :service do
  subject do
    xml_document(:ubl) do |xml|
      described_class.call(xml:, fee:, line_id:)
    end
  end

  let(:fee) { create(:fee, precise_unit_amount: 0.059, taxes_rate:, fee_type:) }
  let(:taxes_rate) { 20.00 }
  let(:fee_type) { :subscription }
  let(:line_id) { 1 }

  let(:root) { "//cac:InvoiceLine" }

  describe ".call" do
    it { is_expected.not_to be_nil }

    it "contains section name as comment" do
      expect(subject).to contains_xml_comment("Line Item #{line_id}: #{fee.invoice_name}")
    end

    it "have the line id" do
      expect(subject).to contains_xml_node("#{root}/cbc:ID")
        .with_value(line_id)
    end

    context "with InvoicedQuantity" do
      it "have the item units" do
        expect(subject).to contains_xml_node("#{root}/cbc:InvoicedQuantity")
          .with_value(fee.units)
          .with_attribute("unitCode", "C62")
      end
    end

    it "have the item total amount" do
      expect(subject).to contains_xml_node("#{root}/cbc:LineExtensionAmount")
        .with_value(fee.amount)
        .with_attribute("currencyID", fee.currency)
    end

    context "when Item" do
      it "have the item name" do
        expect(subject).to contains_xml_node("#{root}/cac:Item/cbc:Name").with_value(fee.item_name)
      end

      context "with ClassifiedTaxCategory" do
        context "with Category ID" do
          let(:xpath) { "#{root}/cac:Item/cac:ClassifiedTaxCategory/cbc:ID" }

          context "when taxes are not zero" do
            it "has the S category code" do
              expect(subject).to contains_xml_node(xpath).with_value("S")
            end
          end

          context "when taxes are zero" do
            let(:taxes_rate) { 0.00 }

            it "has the Z category code" do
              expect(subject).to contains_xml_node(xpath).with_value("Z")
            end
          end

          context "when credit fee" do
            let(:fee_type) { :credit }

            it "has the O category code" do
              expect(subject).to contains_xml_node(xpath).with_value("O")
            end
          end
        end

        context "when Percent" do
          it "have the item taxes rate" do
            expect(subject).to contains_xml_node(
              "#{root}/cac:Item/cac:ClassifiedTaxCategory/cbc:Percent"
            ).with_value(fee.taxes_rate)
          end

          context "with O_CATEGORY" do
            let(:fee_type) { :credit }

            it "do not have percent tag" do
              expect(subject).not_to contains_xml_node(
                "#{root}/cac:Item/cac:ClassifiedTaxCategory/cbc:Percent"
              )
            end
          end
        end

        it "have the item taxes scheme" do
          expect(subject).to contains_xml_node(
            "#{root}/cac:Item/cac:ClassifiedTaxCategory/cac:TaxScheme/cbc:ID"
          ).with_value("VAT")
        end
      end

      context "when AdditionalItemProperty" do
        it "have the item description" do
          expect(subject).to contains_xml_node(
            "#{root}/cac:Item/cac:AdditionalItemProperty/cbc:Name"
          ).with_value("Description")

          expect(subject).to contains_xml_node(
            "#{root}/cac:Item/cac:AdditionalItemProperty/cbc:Value"
          ).with_value(fee.invoice_name)
        end

        context "with fee description field" do
          before { fee.update(description: "Test me") }

          it "uses fee description field" do
            expect(subject).to contains_xml_node(
              "#{root}/cac:Item/cac:AdditionalItemProperty/cbc:Value"
            ).with_value("Test me")
          end
        end
      end
    end

    context "when Price" do
      it "have the item unit amount" do
        expect(subject).to contains_xml_node("#{root}/cac:Price/cbc:PriceAmount")
          .with_value("0.059")
          .with_attribute("currencyID", fee.currency)
      end
    end
  end
end
