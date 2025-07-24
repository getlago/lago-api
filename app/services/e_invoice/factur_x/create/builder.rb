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

        Tax = Data.define(:rate, :amount)
        Payment = Data.define(:type, :amount)
        Discount = Data.define(:indicator, :rate, :amount, :reason)

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
              TradeSettlement.call(xml:, invoice:) do
                TradeSettlementPayment.call(xml:, invoice:, payment: Payment.new(type: TradeSettlementPayment::STANDARD, amount: nil))
                TradeSettlementPayment.call(xml:, invoice:, payment: Payment.new(type: TradeSettlementPayment::PREPAID, amount: 10))
                TradeSettlementPayment.call(xml:, invoice:, payment: Payment.new(type: TradeSettlementPayment::CREDIT_NOTE, amount: 10))

                ApplicableTradeTax.call(xml:, invoice:, tax: Tax.new(rate: 0.19, amount: 15.35))
                ApplicableTradeTax.call(xml:, invoice:, tax: Tax.new(rate: 0.20, amount: 875.65))
                ApplicableTradeTax.call(xml:, invoice:, tax: Tax.new(rate: 0.21, amount: 99.00))

                TradeAllowanceCharge.call(xml:, invoice:, discount: Discount.new(indicator: false, rate: 0.19, amount: 0.16, reason: "Discount 02 (Plan) - 19% portion"))
                TradeAllowanceCharge.call(xml:, invoice:, discount: Discount.new(indicator: false, rate: 0.20, amount: 8.84, reason: "Discount 02 (Plan) - 20% portion"))
                TradeAllowanceCharge.call(xml:, invoice:, discount: Discount.new(indicator: false, rate: 0.21, amount: 1.00, reason: "Discount 02 (Plan) - 21% portion"))
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

        def formatted_date(date)
          date.strftime('%Y%m%d')
        end

        def percent(value)
          format_number(value * 100, "%.2f%%")
        end

        def format_number(value, mask = '%.2f')
          format(mask, value)
        end
      end
    end
  end
end