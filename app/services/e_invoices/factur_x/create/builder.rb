# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class Builder < CreateService
        ROOT_NAMESPACES = {
          "xmlns:xs" => "http://www.w3.org/2001/XMLSchema",
          "xmlns:rsm" => "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100",
          "xmlns:qdt" => "urn:un:unece:uncefact:data:standard:QualifiedDataType:100",
          "xmlns:ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100",
          "xmlns:udt" => "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
        }.freeze

        DATEFORMAT = "%Y%m%d"

        # More date formats for UNTDID 2379 here
        # https://service.unece.org/trade/untdid/d15a/tred/tred2379.htm
        CCYYMMDD = 102

        # More measures codes defined in UNECE Recommendation 20 here
        # https://docs.peppol.eu/pracc/catalogue/1.0/codelist/UNECERec20/
        UNIT_CODE = "C62"

        def initialize(xml:, invoice: nil)
          @xml = xml
          @invoice = invoice
        end

        def call
          xml["rsm"].CrossIndustryInvoice(ROOT_NAMESPACES) {
            xml.comment "Exchange Document Context"
            xml["rsm"].ExchangedDocumentContext do
              xml["ram"].GuidelineSpecifiedDocumentContextParameter do
                xml["ram"].ID "urn:cen.eu:en16931:2017"
              end
            end

            Header.call(xml:, invoice:)

            xml.comment "Supply Chain Trade Transaction"
            xml["rsm"].SupplyChainTradeTransaction do
              build_line_items_for_fees(xml)

              TradeAgreement.call(xml:, invoice:)
              TradeDelivery.call(xml:, invoice:)
              TradeSettlement.call(xml:, invoice:) do
                credits_and_payments do |type, amount|
                  TradeSettlementPayment.call(xml:, invoice:, type:, amount:)
                end
                applied_taxes do |applied_tax|
                  ApplicableTradeTax.call(xml:, invoice:, applied_tax:)
                end
                allowance_charges do |tax_rate, amount|
                  TradeAllowanceCharge.call(xml:, invoice:, tax_rate:, amount:)
                end

                PaymentTerms.call(xml:, invoice:)
                MonetarySummation.call(xml:, invoice:)
              end
            end
          }
        end

        protected

        attr_accessor :xml, :invoice

        def build_line_items_for_fees(xml)
          invoice.fees.each_with_index do |fee, index|
            LineItem.call(xml:, line_id: index + 1, fee:)
          end
        end
      end
    end
  end
end
