# frozen_string_literal: true

module EInvoices
  module Invoices
    module Common
      def resource
        invoice
      end

      def notes
        ["Invoice ID: #{invoice.id}"]
      end

      def invoice_type_code
        if invoice.credit?
          EInvoices::BaseService::PREPAID_INVOICE
        elsif invoice.self_billed?
          EInvoices::BaseService::SELF_BILLED_INVOICE
        else
          EInvoices::BaseService::COMMERCIAL_INVOICE
        end
      end

      def delivery_date
        case invoice.invoice_type
        when "one_off", "credit"
          invoice.created_at
        when "subscription"
          invoice.subscriptions.map do |subscription|
            ::Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)
              .charges_from_datetime
          end.min
        end
      end

      def credits_and_payments(&block)
        {
          EInvoices::BaseService::STANDARD_PAYMENT => invoice.total_due_amount,
          EInvoices::BaseService::PREPAID_PAYMENT => invoice.prepaid_credit_amount,
          EInvoices::BaseService::CREDIT_NOTE_PAYMENT => invoice.credit_notes_amount
        }.each do |type, amount|
          yield(type, amount) if amount.positive?
        end
      end

      def payment_terms_description
        "#{I18n.t("invoice.payment_term")} #{I18n.t("invoice.payment_term_days", net_payment_term: invoice.net_payment_term)}"
      end

      def allowances
        invoice.coupons_amount_cents + invoice.progressive_billing_credit_amount_cents
      end

      def taxes(&block)
        invoice.fees.group_by(&:taxes_rate).map do |tax_rate, fees|
          total_taxes = fees.sum(&:taxes_precise_amount_cents)
          charged_amount = if tax_rate > 0
            (total_taxes * 100).fdiv(tax_rate)
          else
            fees.sum(&:precise_amount_cents) - allowances_per_tax_rate[tax_rate]
          end

          tax_category = tax_category_code(type: invoice.invoice_type, tax_rate: tax_rate)

          yield tax_category, tax_rate, Money.new(charged_amount), Money.new(total_taxes)
        end
      end

      def allowances_per_tax_rate
        invoice.fees.group_by(&:taxes_rate).map do |tax_rate, fees|
          total_amount = fees.sum(&:precise_amount_cents)

          if tax_rate > 0
            total_taxes = fees.sum(&:taxes_precise_amount_cents)
            charged_amount = (total_taxes * 100).fdiv(tax_rate)

            [tax_rate, total_amount - charged_amount]
          else
            [tax_rate, total_amount.fdiv(invoice.fees.sum(:precise_amount_cents)) * allowances]
          end
        end.to_h
      end
    end
  end
end
