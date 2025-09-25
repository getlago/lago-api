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
    end
  end
end
