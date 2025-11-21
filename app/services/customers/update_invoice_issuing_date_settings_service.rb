# frozen_string_literal: true

module Customers
  class UpdateInvoiceIssuingDateSettingsService < BaseService
    def initialize(customer:, params:)
      @customer = customer
      @params = params
      @old_issuing_date_settings = {
        invoice_grace_period: customer.invoice_grace_period,
        subscription_invoice_issuing_date_anchor: customer.subscription_invoice_issuing_date_anchor,
        subscription_invoice_issuing_date_adjustment: customer.subscription_invoice_issuing_date_adjustment
      }
      super
    end

    def call
      set_issuing_date_settings

      if customer.changed? && customer.save!
        # NOTE: Update issuing_date on draft invoices.
        customer.invoices.draft.find_each do |invoice|
          invoice.issuing_date = invoice.issuing_date + issuing_date_adjustment(invoice)
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

    attr_reader :customer, :params, :old_issuing_date_settings

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

    def issuing_date_adjustment(invoice)
      recurring = invoice.invoice_subscriptions.first&.recurring?

      old_issuing_date_adjustment = Invoices::IssuingDateService.new(
        customer: old_issuing_date_settings,
        billing_entity: customer.billing_entity,
        recurring:
      ).issuing_date_adjustment

      new_issuing_date_adjustment = Invoices::IssuingDateService.new(
        customer: customer,
        billing_entity: customer.billing_entity,
        recurring:
      ).issuing_date_adjustment

      new_issuing_date_adjustment - old_issuing_date_adjustment
    end

    def grace_period_payment_due_date(invoice)
      invoice.issuing_date + customer.applicable_net_payment_term.days
    end
  end
end
