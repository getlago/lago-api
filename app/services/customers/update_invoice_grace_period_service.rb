# frozen_string_literal: true

module Customers
  class UpdateInvoiceGracePeriodService < BaseService
    def initialize(customer:, grace_period:)
      @customer = customer
      @grace_period = grace_period
      super
    end

    def call
      ActiveRecord::Base.transaction do
        customer.update!(invoice_grace_period: grace_period)

        # NOTE: Finalize related draft invoices.
        customer.invoices.ready_to_be_finalized.each do |invoice|
          Invoices::FinalizeService.call(invoice:)
        end

        # NOTE: Update issuing_date on draft invoices.
        customer.invoices.draft.each do |invoice|
          invoice.update!(issuing_date: grace_period_issuing_date(invoice))
        end

        result.customer = customer
        result
      end
    end

    private

    attr_reader :customer, :grace_period

    def invoice_created_at(invoice)
      invoice.created_at.in_time_zone(customer.applicable_timezone).to_date
    end

    def grace_period_issuing_date(invoice)
      invoice_created_at(invoice) + customer.applicable_invoice_grace_period.days
    end
  end
end
