# frozen_string_literal: true

module EInvoices
  module CreditNotes::Ubl
    class Builder < EInvoices::Ubl::BaseService
      include CreditNotes::Common

      def initialize(xml:, credit_note:)
        super(xml:, resource: credit_note)

        @credit_note = credit_note
      end

      def call
        xml.CreditNote(ROOT_NAMESPACES) do
          xml.comment "UBL Version and Customization"
          xml["cbc"].UBLVersionID "2.1"
          xml["cbc"].CustomizationID "urn:cen.eu:en16931:2017"

          Ubl::Header.call(xml:, resource:, type_code: CREDIT_NOTE, notes:)
          Ubl::BillingReference.call(xml:, resource: invoice)

          Ubl::SupplierParty.call(xml:, resource:)
          Ubl::CustomerParty.call(xml:, resource:)

          Ubl::PaymentMeans.call(xml:, type: STANDARD_PAYMENT)
          Ubl::PaymentTerms.call(xml:, note: "Credit note - immediate settlement")

          allowance_charges(invoice) do |tax_rate, amount|
            Ubl::AllowanceCharge.call(xml:, resource:, indicator: INVOICE_CHARGE, tax_rate:, amount:)
          end

          xml.comment "Tax Total Information"
          xml["cac"].TaxTotal do
            xml["cbc"].TaxAmount format_number(Money.new(-invoice.taxes_amount_cents)), currencyID: credit_note.currency

            taxes(invoice) do |tax_category, tax_rate, basis_amount, tax_amount|
              Ubl::TaxSubtotal.call(xml:, resource:, tax_category:, tax_rate:, basis_amount: -basis_amount, tax_amount: -tax_amount)
            end
          end

          Ubl::MonetaryTotal.call(xml:, resource:, amounts: monetary_summation_amounts)

          line_items do |fee, line_id|
            Ubl::LineItem.call(xml:, resource:, fee:, line_id:)
          end
        end
      end

      private

      attr_accessor :xml, :credit_note

      def invoice
        credit_note.invoice
      end

      def monetary_summation_amounts
        Ubl::MonetaryTotal::Amounts.new(
          line_extension_amount: -invoice.fees_amount,
          tax_exclusive_amount: -invoice.sub_total_excluding_taxes_amount,
          tax_inclusive_amount: -invoice.sub_total_including_taxes_amount,
          charge_total_amount: Money.new(allowances(invoice)),
          prepaid_amount: -(invoice.prepaid_credit_amount + invoice.credit_notes_amount),
          payable_amount: -invoice.total_amount
        )
      end
    end
  end
end
