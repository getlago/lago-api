# frozen_string_literal: true

module Customers
  class UpdateInvoiceIssuingDateSettingsService < BaseService
    def initialize(customer:, params:)
      @customer = customer
      @params = params
      super
    end

    def call
      old_recurring_adjustment = customer.invoice_issuing_date_adjustment
      old_grace_period = customer.applicable_invoice_grace_period

      set_issuing_date_settings

      if customer.changed? && customer.save!
        # NOTE: Update issuing_date on draft invoices.
        customer.invoices.draft.find_each do |invoice|
          grace_period_diff = grace_period_diff(invoice, old_recurring_adjustment, old_grace_period)

          invoice.issuing_date = invoice.issuing_date + grace_period_diff.days
          invoice.payment_due_date = grace_period_payment_due_date(invoice)
          invoice.save!
        end

        customer.invoices.ready_to_be_finalized.find_each do |invoice|
          Invoices::FinalizeJob.perform_later(invoice)
        end
      end

      result.customer = customer
      result
    end

    private

    attr_reader :customer, :params

    def set_issuing_date_settings
      billing_configuration = params[:billing_configuration]&.to_h || {}

      if billing_configuration.key?(:subscription_invoice_issuing_date_anchor)
        customer.subscription_invoice_issuing_date_anchor = billing_configuration[:subscription_invoice_issuing_date_anchor]
      end

      if billing_configuration.key?(:subscription_invoice_issuing_date_adjustment)
        customer.subscription_invoice_issuing_date_adjustment = billing_configuration[:subscription_invoice_issuing_date_adjustment]
      end

      if License.premium? && params.key?(:invoice_grace_period)
        customer.invoice_grace_period = params[:invoice_grace_period]
      end

      if License.premium? && billing_configuration.key?(:invoice_grace_period)
        customer.invoice_grace_period = billing_configuration[:invoice_grace_period]
      end
    end

    def grace_period_diff(invoice, old_recurring_adjustment, old_grace_period)
      recurring = invoice.invoice_subscriptions.first&.recurring?

      if recurring
        customer.invoice_issuing_date_adjustment - old_recurring_adjustment
      else
        customer.applicable_invoice_grace_period - old_grace_period
      end
    end

    def grace_period_payment_due_date(invoice)
      invoice.issuing_date + customer.applicable_net_payment_term.days
    end
  end
end
