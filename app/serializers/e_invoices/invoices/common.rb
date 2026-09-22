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
          EInvoices::BaseSerializer::PREPAID_INVOICE
        elsif invoice.self_billed?
          EInvoices::BaseSerializer::SELF_BILLED_INVOICE
        else
          EInvoices::BaseSerializer::COMMERCIAL_INVOICE
        end
      end

      def delivery_date
        case invoice.invoice_type
        when "one_off", "credit"
          invoice.created_at
        when "subscription", "progressive_billing"
          invoice.subscriptions.map do |subscription|
            ::Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)
              .charges_from_datetime
          end.min
        end
      end

      def credits_and_payments(&block)
        {
          EInvoices::BaseSerializer::STANDARD_PAYMENT => invoice.total_due_amount,
          EInvoices::BaseSerializer::PREPAID_PAYMENT => invoice.prepaid_credit_amount,
          EInvoices::BaseSerializer::CREDIT_NOTE_PAYMENT => invoice.credit_notes_amount
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
        grouped_fees = invoice.fees.group_by(&:taxes_rate)
        # Tax bases retain their precision, while monetary subtotals must add up to
        # the booked invoice total, including any rounding across fees or tax rates.
        booked_amounts = Integrations::Aggregator::Taxes::Allocation.by_group(
          invoice.taxes_amount_cents, grouped_fees.values,
          amount: invoice.provider_taxes? ? :taxes_amount_cents : :taxes_precise_amount_cents,
          precise_amount: :taxes_precise_amount_cents
        )

        grouped_fees.map.with_index do |(tax_rate, fees), index|
          charged_amount = if tax_rate > 0
            taxable_amount_cents(fees, tax_rate)
          else
            fees.sum(&:precise_amount_cents) - allowances_per_tax_rate[tax_rate]
          end

          tax_category = tax_category_code(type: invoice.invoice_type, tax_rate: tax_rate)

          yield tax_category, tax_rate, Money.new(charged_amount), Money.new(booked_amounts[index])
        end
      end

      def allowances_per_tax_rate
        fees_total = invoice.fees.sum(:precise_amount_cents)

        invoice.fees.group_by(&:taxes_rate).map do |tax_rate, fees|
          total_amount = fees.sum(&:precise_amount_cents)

          if tax_rate > 0
            charged_amount = taxable_amount_cents(fees, tax_rate)

            [tax_rate, total_amount - charged_amount]
          else
            proportion = fees_total.zero? ? 0 : total_amount.fdiv(fees_total)
            [tax_rate, proportion * allowances]
          end
        end.to_h
      end

      private

      def taxable_amount_cents(fees, tax_rate)
        fees.sum do |fee|
          inferred_base = fee.taxes_precise_amount_cents * 100 / tax_rate.to_d
          # A provider's rounded-up tax must not create a base larger than the fee.
          [inferred_base, fee.sub_total_excluding_taxes_precise_amount_cents].min
        end
      end
    end
  end
end
