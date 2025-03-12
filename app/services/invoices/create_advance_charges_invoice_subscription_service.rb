# frozen_string_literal: true

module Invoices
  class CreateAdvanceChargesInvoiceSubscriptionService < BaseService
    Result = BaseResult

    def initialize(invoice:, timestamp:, subscriptions:)
      @invoice = invoice
      @timestamp = timestamp
      @subscriptions = subscriptions

      super
    end

    # Since the `advance_charges` invoice only have charges by design,
    # we apply the `charges_(from|to)_date for both charges and subscriptions period
    # See https://github.com/getlago/lago-api/pull/3327 for details
    def call
      latest_subscription = subscriptions.max_by(&:started_at)
      boundaries = calculate_boundaries(latest_subscription)

      subscriptions.each do |subscription|
        invoice.invoice_subscriptions << InvoiceSubscription.create!(
          invoice:,
          subscription:,
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

    attr_reader :invoice, :timestamp, :subscriptions

    def calculate_boundaries(subscription)
      date_service = Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: false)

      {
        from: date_service.charges_from_datetime,
        to: date_service.charges_to_datetime
      }
    end
  end
end
