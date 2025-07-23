# frozen_string_literal: true

module EInvoice
  module FacturX
    class Base < BaseService
      ROOT_NAMESPACES = {
        "xmlns:rsm" => "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100",
        "xmlns:qdt" => "urn:un:unece:uncefact:data:standard:QualifiedDataType:100",
        "xmlns:ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100",
        "xmlns:xs"  => "http://www.w3.org/2001/XMLSchema",
        "xmlns:udt" => "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
      }.freeze

      def self.persist(invoice:, filename: "output.xml")
        new(invoice:).persist(filename:)
      end

      def initialize(invoice:)
        @invoice = invoice
      end

      def build
        Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          xml["rsm"].CrossIndustryInvoice(ROOT_NAMESPACES) {
            ContextBuilder.new(xml).call
            HeaderBuilder.new(xml, invoice:).call
            TradeTransaction.new(xml, invoice:).call do
              5.times do |index|
                line_item = line_items_attrs_gen
                line_item.merge!({
                  line_id: index + 1,
                  line_total_amount: line_item[:billed_quantity] * line_item[:charge_amount]
                })

                LineItem.new(xml).call(attrs: line_item)

                TradeAgreement.new(xml).call
                TradeDelivery.new(xml).call
              end
            end
          }
        end.to_xml
      end

      def persist(filename: "output.xml")
        File.write(filename, build)
      end

      private

      attr_accessor :invoice

      def line_items_attrs_gen
        {
          name: SecureRandom.hex(10),
          description: SecureRandom.hex(40),
          charge_amount: rand(1.0..100.0),
          billed_quantity: rand(1..100),
          rate_applicable_percent: 20.00,
        }
      end
    end
  end
end