# frozen_string_literal: true

module EInvoices
  module Invoices::FacturX
    class Builder < EInvoices::FacturX::BaseService
      include Invoices::Common

      def initialize(xml:, invoice:)
        super(xml:, resource: invoice)

        @xml = xml
        @invoice = invoice
      end

      def call
        FacturX::CrossIndustryInvoice.call(xml:) do
          FacturX::Header.call(xml:, resource: invoice, type_code: invoice_type_code, notes:)

          xml.comment "Supply Chain Trade Transaction"
          xml["rsm"].SupplyChainTradeTransaction do
            line_items do |fee, line_id|
              FacturX::LineItem.call(xml:, resource:, data: line_item_data(line_id, fee))
            end

            FacturX::TradeAgreement.call(xml:, resource:, options: trade_aggreement_options)
            FacturX::TradeDelivery.call(xml:, delivery_date:)
            FacturX::TradeSettlement.call(xml:, resource:) do
              credits_and_payments do |type, amount|
                FacturX::TradeSettlementPayment.call(xml:, resource:, type:, amount:)
              end

              taxes(invoice) do |tax_category, tax_rate, basis_amount, tax_amount|
                FacturX::ApplicableTradeTax.call(xml:, tax_category:, tax_rate:, basis_amount:, tax_amount:)
              end

              allowance_charges(invoice) do |tax_rate, amount|
                FacturX::TradeAllowanceCharge.call(xml:, resource:, indicator: INVOICE_DISCOUNT, tax_rate:, amount:)
              end

              FacturX::PaymentTerms.call(xml:, due_date: invoice.payment_due_date, description: payment_terms_description)
              FacturX::MonetarySummation.call(xml:, resource:, amounts: monetary_summation_amounts)
            end
          end
        end
      end

      private

      attr_accessor :xml, :invoice

      def trade_aggreement_options
        FacturX::TradeAgreement::Options.new(
          tax_registration: !invoice.credit?
        )
      end

      def monetary_summation_amounts
        FacturX::MonetarySummation::Amounts.new(
          line_total_amount: invoice.fees_amount,
          allowances_amount: Money.new(allowances(invoice)),
          tax_basis_amount: invoice.sub_total_excluding_taxes_amount,
          tax_amount: invoice.taxes_amount,
          grand_total_amount: invoice.sub_total_including_taxes_amount,
          prepaid_amount: invoice.prepaid_credit_amount + invoice.credit_notes_amount,
          due_payable_amount: invoice.total_amount
        )
      end

      def line_item_data(index, fee)
        category = tax_category_code(type: fee.fee_type, tax_rate: fee.taxes_rate)
        FacturX::LineItem::Data.new(
          line_id: index,
          name: fee.item_name,
          description: fee_description(fee),
          charge_amount: fee.precise_unit_amount,
          billed_quantity: fee.units,
          category_code: category,
          rate_percent: (category != O_CATEGORY) ? fee.taxes_rate : nil,
          line_total_amount: fee.amount
        )
      end
    end
  end
end
