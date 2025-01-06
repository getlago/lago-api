# frozen_string_literal: true

module Invoices
  class PreviewService < BaseService
    def initialize(customer:, subscription:, targeted_at:)
      @customer = customer
      @subscription = subscription
      @targeted_at = targeted_at

      super
    end


    # SIMULATE CURRENT USAGE
    def call
      puts "\n\n\n\nSUBSCRIPTION: #{subscription.inspect}\n\n\n\n"
      return result.not_found_failure!(resource: 'customer') unless customer
      return result.not_found_failure!(resource: 'subscription') unless subscription

      @invoice = Invoice.new(
        organization: customer.organization,
        customer:,
        invoice_type: :subscription,
        currency: subscription.plan&.amount_currency,
        timezone: customer.applicable_timezone,
        issuing_date:,
        payment_due_date:,
        created_at: Time.current,
        updated_at: Time.current
      )

      puts "\n\n\n\nBOUNDARIES: #{boundaries.inspect}\n\n\n\n"

      fee_result = Fees::SubscriptionService.new(invoice:, subscription:, boundaries:, preview: true).create
      invoice.fees = [fee_result.fee]

      puts "\n\n\n\nfee_result: #{fee_result.fee.inspect}\n\n\n\n"

      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)

      invoice.fees.each do |fee|
        taxes_result = Fees::ApplyTaxesService.call(fee:)
        taxes_result.raise_if_error!
      end

      taxes_result = Invoices::ApplyTaxesService.call(invoice:)
      taxes_result.raise_if_error!

      invoice.total_amount_cents = invoice.fees_amount_cents + invoice.taxes_amount_cents

      result.invoice = invoice
      result
    end

    private

    attr_accessor :customer, :subscription, :targeted_at, :invoice

    def boundaries
      {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        timestamp: billing_time
      }
    end

    def date_service
      current_usage = targeted_at.present?

      Subscriptions::DatesService.new_instance(subscription, billing_time, current_usage:)
    end

    def billing_time
      return @billing_time if defined? @billing_time

      ds = Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)

      @billing_time = targeted_at ? targeted_at : (ds.end_of_period + 1.day)
    end

    def issuing_date
      billing_time.in_time_zone(customer.applicable_timezone).to_date
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end
  end
end
