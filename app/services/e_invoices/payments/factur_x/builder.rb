# frozen_string_literal: true

module EInvoices
  module Payments::FacturX
    class Builder < EInvoices::FacturX::BaseService
      include Payments::Common

      def initialize(xml:, payment:)
        super(xml:, resource: payment)

        @xml = xml
        @payment = payment
      end

      def call
        FacturX::CrossIndustryInvoice.call(xml:) do
          FacturX::Header.call(xml:, resource: payment_receipt, type_code: PAYMENT_RECEIPT, notes:)

          xml.comment "Supply Chain Trade Transaction"
          xml["rsm"].SupplyChainTradeTransaction do
            FacturX::LineItem.call(xml:, resource:, data: line_item_data)
            FacturX::TradeAgreement.call(xml:, resource:, options: trade_aggreement_options)
            FacturX::TradeDelivery.call(xml:, delivery_date: payment.created_at)
            FacturX::TradeSettlement.call(xml:, resource:) do
              credits_and_payments do |type, amount|
                FacturX::TradeSettlementPayment.call(xml:, resource:, type:, amount:)
              end

              FacturX::ApplicableTradeTax.call(xml:, tax_category: Z_CATEGORY, tax_rate: 0.0, basis_amount: Money.new(payment.amount_cents), tax_amount: 0.0)
              FacturX::PaymentTerms.call(xml:, due_date: payment.created_at, description: payment_terms_description)
              FacturX::MonetarySummation.call(xml:, resource:, amounts: monetary_summation_amounts)

              FacturX::InvoiceReference.call(xml:, invoice_reference: payment.invoices.pluck(:number).to_sentence)
            end
          end
        end
      end

      private

      attr_accessor :xml, :payment

      def payment_receipt
        payment.payment_receipt
      end

      def payment_terms_description
        "#{pay_method.to_s.titleize} payment received on  #{payment.created_at}"
      end

      def pay_method
        return "manual" if payment.payment_type_manual?
        return "provider" if payment.provider_payment_method_data.blank?

        payment.provider_payment_method_data["type"]
      end

      def paid_using_card?
        return false if payment.payment_type_manual?
        return false if payment.provider_payment_method_data.blank?

        payment.provider_payment_method_data["type"] == "card"
      end

      def monetary_summation_amounts
        FacturX::MonetarySummation::Amounts.new(
          line_total_amount: payment.amount,
          tax_basis_amount: payment.amount,
          tax_amount: 0,
          grand_total_amount: payment.amount,
          prepaid_amount: payment.amount,
          due_payable_amount: 0
        )
      end

      def line_item_data
        FacturX::LineItem::Data.new(
          line_id: 1,
          name: "Payment Received",
          description: "Payment received via #{payment_mode} for invoice #{invoice_numbers}",
          charge_amount: payment.amount,
          billed_quantity: 1,
          category_code: Z_CATEGORY,
          rate_percent: 0.0,
          line_total_amount: payment.amount
        )
      end

      def trade_aggreement_options
        FacturX::TradeAgreement::Options.new(
          tax_registration: true
        )
      end

      def invoice_numbers
        payment.invoices.pluck(:number).to_sentence
      end

      def notes
        ["Receipt for payment of #{payment.amount_currency} #{payment.amount} received via #{payment_mode} for invoice #{invoice_numbers}"]
      end

      def payment_mode
        case payment.payment_type
        when "manual"
          "Manual"
        else "provider"
          payment.payment_provider_type
        end
      end

    end
  end
end
