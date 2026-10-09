# frozen_string_literal: true

module Invoices
  class CreateAdvanceChargesInvoiceService < BaseService
    Result = BaseResult

    def initialize(invoice:, timestamp:, billing_contexts_with_fees:, all_billing_contexts:)
      @invoice = invoice
      @timestamp = timestamp
      @billing_contexts_with_fees = billing_contexts_with_fees
      @all_billing_contexts = all_billing_contexts

      super
    end

    # Since the `advance_charges` invoice only have charges by design,
    # we apply the `charges_(from|to)_date for both charges and subscriptions period
    # See https://github.com/getlago/lago-api/pull/3327 for details
    def call
      boundaries = calculate_boundaries(latest_billing_context)

      billing_contexts_with_fees.each do |billing_context|
        invoice.invoice_subscriptions << InvoiceSubscription.create!(
          organization: billing_context.organization,
          invoice:,
          subscription: billing_context.subscription,
          timestamp:,
          from_datetime: boundaries[:from],
          to_datetime: boundaries[:to],
          charges_from_datetime: boundaries[:from],
          charges_to_datetime: boundaries[:to],
          recurring: false,
          invoicing_reason: :in_advance_charge_periodic
        )
      end

      result
    end

    private

    attr_reader :invoice, :timestamp, :billing_contexts_with_fees, :all_billing_contexts

    def latest_billing_context
      all_billing_contexts.reject { |billing_context| billing_context.terminated_at?(timestamp) }.max_by(&:started_at) ||
        all_billing_contexts.max_by(&:terminated_at)
    end

    def calculate_boundaries(billing_context)
      subscription = billing_context.subscription
      date_service = Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: false)

      {
        from: date_service.charges_from_datetime,
        to: date_service.charges_to_datetime
      }
    end
  end
end
