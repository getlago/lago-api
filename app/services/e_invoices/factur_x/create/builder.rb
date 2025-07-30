# frozen_string_literal: true

module EInvoices
  module FacturX
    module Create
      class Builder < ::BaseService
        ROOT_NAMESPACES = {
          "xmlns:xs" => "http://www.w3.org/2001/XMLSchema",
          "xmlns:rsm" => "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100",
          "xmlns:qdt" => "urn:un:unece:uncefact:data:standard:QualifiedDataType:100",
          "xmlns:ram" => "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100",
          "xmlns:udt" => "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
        }.freeze

        # More taxations defined on UNTDID 5153 here
        # https://service.unece.org/trade/untdid/d00a/tred/tred5153.htm
        VAT = "VAT"

        # More categories for UNTDID 5305 here
        # https://service.unece.org/trade/untdid/d00a/tred/tred5305.htm
        S_CATEGORY = "S"
        Z_CATEGORY = "Z"

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
                build_settlement_payments(xml, invoice)
                build_applied_taxes(xml, invoice)
                build_allowance_charges(xml, invoice)

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

        def build_settlement_payments(xml, invoice)
          {
            TradeSettlementPayment::STANDARD => invoice.total_due_amount,
            TradeSettlementPayment::PREPAID => invoice.prepaid_credit_amount,
            TradeSettlementPayment::CREDIT_NOTE => invoice.credit_notes_amount
          }.each do |type, amount|
            TradeSettlementPayment.call(xml:, invoice:, type:, amount:) if amount.positive?
          end
        end

        def build_applied_taxes(xml, invoice)
          if invoice.applied_taxes.empty?
            zero_tax = Invoice::AppliedTax.new(fees_amount: invoice.sub_total_excluding_taxes_amount)
            ApplicableTradeTax.call(xml:, invoice:, applied_tax: zero_tax)
          else
            invoice.applied_taxes.each do |applied_tax|
              ApplicableTradeTax.call(xml:, invoice:, applied_tax:)
            end
          end
        end

        def build_allowance_charges(xml, invoice)
          return unless invoice.coupons_amount_cents.positive?

          sum_by_taxes_rate = invoice.fees.group(:taxes_rate).order(taxes_rate: :asc).sum(:amount_cents)
          total_without_taxes = sum_by_taxes_rate.values.sum
          coupon_proportions = sum_by_taxes_rate.transform_values do |value|
            Money.new((value.to_f / total_without_taxes) * invoice.coupons_amount_cents)
          end
          coupon_proportions.each do |tax_rate, amount|
            TradeAllowanceCharge.call(xml:, invoice:, tax_rate:, amount:)
          end
        end

        def formatted_date(date)
          date.strftime("%Y%m%d")
        end

        def percent(value)
          format_number(value, "%.2f%%")
        end

        def format_number(value, mask = "%.2f")
          format(mask, value)
        end

        def tax_category(rate)
          rate.zero? ? Z_CATEGORY : S_CATEGORY
        end
      end
    end
  end
end
