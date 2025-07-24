# frozen_string_literal: true

module EInvoice
  module FacturX
    module Create
      class Builder < ::BaseService
        ROOT_NAMESPACES = {
          "xmlns:rsm" => "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100",
          "xmlns:qdt" => "urn:un:unece:uncefact:data:standard:QualifiedDataType:100",
          "xmlns:ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100",
          "xmlns:xs"  => "http://www.w3.org/2001/XMLSchema",
          "xmlns:udt" => "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
        }.freeze

        def initialize(xml:, invoice: nil)
          @xml = xml
          @invoice = invoice
        end

        def call
          xml["rsm"].CrossIndustryInvoice(ROOT_NAMESPACES) {
            Context.call(xml:)
            Header.call(xml:, invoice:)
            TradeTransaction.call(xml:, invoice:) do
              build_line_items_for_fees(xml)

              TradeAgreement.call(xml:)
              TradeDelivery.call(xml:)
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