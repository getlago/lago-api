# frozen_string_literal: true

module Invoices
  class CreateGeneratingService < BaseService
    def initialize(customer:, invoice_type:, datetime:, currency:, subscriptions_details: nil, charge_in_advance: false)
      @customer = customer
      @invoice_type = invoice_type
      @currency = currency
      @datetime = datetime
      @charge_in_advance = charge_in_advance
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

        yield invoice if block_given?
      end

      result
    end

    private

    attr_accessor :customer, :invoice_type, :currency, :datetime, :subscriptions_details, :charge_in_advance

    delegate :organization, to: :customer

    # NOTE: accounting date must be in customer timezone
    def issuing_date
      date = datetime.in_time_zone(customer.applicable_timezone).to_date
      return date if !grace_period? || charge_in_advance

      date + customer.applicable_invoice_grace_period.days
    end

    def grace_period?
      return false unless invoice_type.to_sym == :subscription

      customer.applicable_invoice_grace_period.positive?
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end
  end
end
