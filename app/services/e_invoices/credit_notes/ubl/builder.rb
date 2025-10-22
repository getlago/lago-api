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
        xml.CreditNote(CREDIT_NOTE_NAMESPACES) do
          xml.comment "UBL Version and Customization"
          xml["cbc"].UBLVersionID "2.1"
          xml["cbc"].CustomizationID "urn:cen.eu:en16931:2017"

          Ubl::Header.call(xml:, resource:, type_code: CREDIT_NOTE, notes:)
          Ubl::BillingReference.call(xml:, resource: invoice)

          Ubl::SupplierParty.call(xml:, resource:, options: supplier_party_options)
          Ubl::CustomerParty.call(xml:, resource:)

          Ubl::PaymentMeans.call(xml:, type: STANDARD_PAYMENT)
          Ubl::PaymentTerms.call(xml:, note: "Credit note - immediate settlement")

          allowance_charges do |tax_rate, amount|
            Ubl::AllowanceCharge.call(xml:, resource:, indicator: INVOICE_CHARGE, tax_rate:, amount:)
          end

          xml.comment "Tax Total Information"
          xml["cac"].TaxTotal do
            xml["cbc"].TaxAmount format_number(-Money.new(credit_note.precise_taxes_amount_cents)), currencyID: credit_note.currency

            taxes do |tax_category, tax_rate, basis_amount, tax_amount|
              Ubl::TaxSubtotal.call(xml:, resource:, tax_category:, tax_rate:, basis_amount: -basis_amount, tax_amount: -tax_amount)
            end
          end

          Ubl::MonetaryTotal.call(xml:, resource:, amounts: monetary_summation_amounts)

          line_items(:items) do |item, line_id|
            Ubl::LineItem.call(xml:, resource:, data: line_item_data(line_id, item))
          end
        end
      end

      private

      attr_accessor :xml, :credit_note

      def invoice
        credit_note.invoice
      end

      def supplier_party_options
        Ubl::SupplierParty::Options.new(
          tax_registration: !invoice.credit?
        )
      end

      def monetary_summation_amounts
        Ubl::MonetaryTotal::Amounts.new(
          line_extension_amount: -Money.new(credit_note.items.sum(:precise_amount_cents)),
          tax_exclusive_amount: -Money.new(credit_note.sub_total_excluding_taxes_amount_cents),
          tax_inclusive_amount: -Money.new(credit_note.sub_total_including_taxes_amount_cents),
          charge_total_amount: Money.new(credit_note.precise_coupons_adjustment_amount_cents),
          prepaid_amount: 0,
          payable_amount: -Money.new(credit_note.precise_total)
        )
      end

      def line_item_data(index, item)
        category = tax_category_code(type: item.fee.fee_type, tax_rate: item.fee.taxes_rate)
        Ubl::LineItem::Data.new(
          type: :credit_note,
          line_id: index,
          quantity: -(item.fee_rate * item.fee.units),
          line_extension_amount: -item.amount,
          currency: item.amount_currency,
          item_name: item.fee.item_name,
          item_category: category,
          item_rate_percent: (category != O_CATEGORY) ? item.fee.taxes_rate : nil,
          item_description: fee_description(item.fee),
          price_amount: item.fee.precise_unit_amount
        )
      end
    end
  end
end
