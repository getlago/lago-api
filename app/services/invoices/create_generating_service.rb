# frozen_string_literal: true

module Invoices
  class CreateGeneratingService < BaseService
    SubscriptionDetails = Struct.new(:subscription, :boundaries, :recurring)

    def initialize(customer:, invoice_type:, datetime:, currency:, subscriptions_details: nil)
      @customer = customer
      @invoice_type = invoice_type
      @currency = currency
      @datetime = datetime
      @subscriptions_details = subscriptions_details

      super
    end

    def call
      ActiveRecord::Base.transaction do
        invoice = Invoice.create!(
          organization:,
          customer:,
          invoice_type:,
          currency:,
          timezone: customer.applicable_timezone,
          status: :generating,
          issuing_date:,
          payment_due_date:,
          net_payment_term: customer.applicable_net_payment_term,
        )
        result.invoice = invoice

        create_invoice_subscriptions if invoice_type.to_sym == :subscription
      end

      result
    end

    private

    attr_accessor :customer, :invoice_type, :currency, :datetime, :subscriptions_details

    delegate :organization, to: :customer

    def issuing_date
      date = datetime.in_time_zone(customer.applicable_timezone).to_date
      return date unless grace_period?

      date + customer.applicable_invoice_grace_period.days
    end

    def grace_period?
      return false unless invoice_type.to_sym == :subscription

      customer.applicable_invoice_grace_period.positive?
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end

    def create_invoice_subscriptions
      subscriptions_details.each do |subscription_details|
        boundaries = subscription_details.boundaries

        InvoiceSubscription.create!(
          invoice: result.invoice,
          subscription: subscription_details.subscription,
          timestamp: boundaries[:timestamp],
          from_datetime: boundaries[:from_datetime],
          to_datetime: boundaries[:to_datetime],
          charges_from_datetime: boundaries[:charges_from_datetime],
          charges_to_datetime: boundaries[:charges_to_datetime],
          recurring: subscription_details.recurring,
        )
      end
    end
  end
end
