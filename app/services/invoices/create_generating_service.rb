# frozen_string_literal: true

module Invoices
  class CreateGeneratingService < BaseService
    def initialize(customer:, invoice_type:, datetime:, currency:, skip_charges: false)
      @customer = customer
      @invoice_type = invoice_type
      @currency = currency
      @datetime = datetime
      @skip_charges = skip_charges

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
          skip_charges:
        )
        result.invoice = invoice

        yield invoice if block_given?
      end

      result
    end

    private

    attr_accessor :customer, :invoice_type, :currency, :datetime, :skip_charges

    delegate :organization, to: :customer

    # NOTE: accounting date must be in customer timezone
    def issuing_date
      date = datetime.in_time_zone(customer.applicable_timezone).to_date

      if should_use_grace_period?
        date + customer.applicable_invoice_grace_period.days
      else
        date
      end
    end

    def should_use_grace_period?
      if invoice_type.to_sym == :subscription
        customer.applicable_invoice_grace_period.positive?
      else
        false
      end
    end

    def payment_due_date
      (issuing_date + customer.applicable_net_payment_term.days).to_date
    end
  end
end
