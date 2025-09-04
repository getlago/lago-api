# frozen_string_literal: true

module EInvoices
  module CreditNotes::FacturX
    class Builder < EInvoices::FacturX::BaseService
      include CreditNotes::Common

      def initialize(xml:, credit_note:)
        super(xml:, resource: credit_note)

        @xml = xml
        @credit_note = credit_note
      end

      def call
        FacturX::CrossIndustryInvoice.call(xml:) do
          FacturX::Header.call(xml:, resource:, type_code: CREDIT_NOTE, notes:)

          xml.comment "Supply Chain Trade Transaction"
          xml["rsm"].SupplyChainTradeTransaction do
            line_items do |fee, line_id|
              FacturX::LineItem.call(xml:, resource:, fee:, line_id:)
            end

            FacturX::TradeAgreement.call(xml:, resource:)
            FacturX::TradeDelivery.call(xml:, delivery_date: credit_note.created_at)
            FacturX::TradeSettlement.call(xml:, resource:) do
              credits_and_payments do |type, amount|
                FacturX::TradeSettlementPayment.call(xml:, resource:, type:, amount:)
              end

              taxes(credit_note.invoice) do |tax_category, tax_rate, basis_amount, tax_amount|
                FacturX::ApplicableTradeTax.call(xml:, tax_category:, tax_rate:, basis_amount: -basis_amount, tax_amount: -tax_amount)
              end

              allowance_charges(credit_note.invoice) do |tax_rate, amount|
                FacturX::TradeAllowanceCharge.call(xml:, resource:, indicator: INVOICE_CHARGE, tax_rate:, amount: amount)
              end

              FacturX::PaymentTerms.call(xml:, due_date: credit_note.created_at, description: "Credit note - immediate settlement")
              FacturX::MonetarySummation.call(xml:, resource:, amounts: monetary_summation_amounts)
            end
          end
        end
      end

      private

      attr_accessor :xml, :credit_note

      def monetary_summation_amounts
        FacturX::MonetarySummation::Amounts.new(
          line_total_amount: Money.new(-credit_note.fees.sum(:amount_cents)),
          charges_amount: credit_note.coupons_adjustment_amount,
          tax_basis_amount: -credit_note.sub_total_excluding_taxes_amount,
          tax_amount: -credit_note.taxes_amount,
          grand_total_amount: -credit_note.total_amount,
          due_payable_amount: -credit_note.credit_amount
        )
      end
    end
  end
end
