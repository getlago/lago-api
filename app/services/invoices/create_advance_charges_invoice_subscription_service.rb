# frozen_string_literal: true

module Invoices
  class CreateAdvanceChargesInvoiceSubscriptionService < BaseService
    Result = BaseResult[:invoice_subscriptions]

    def initialize(invoice:, timestamp:, billing_periods:)
      @invoice = invoice
      @timestamp = timestamp
      @billing_periods = billing_periods

      super
    end

    def call
      result.invoice_subscriptions = []

      billing_periods.each do |boundaries|
        result.invoice_subscriptions << InvoiceSubscription.create!(
          invoice:,
          subscription_id: boundaries[:subscription_id],
          timestamp:,
          from_datetime: boundaries[:from_datetime],
          to_datetime: boundaries[:to_datetime],
          charges_from_datetime: boundaries[:charges_from_datetime],
          charges_to_datetime: boundaries[:charges_to_datetime],
          recurring: false,
          invoicing_reason: :in_advance_charge_periodic
        )
      end

      result
    end

    private

    attr_accessor :invoice, :timestamp, :billing_periods
  end
end
