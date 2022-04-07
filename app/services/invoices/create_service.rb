# frozen_string_literal: true

module Invoices
  class CreateService < BaseService
    def initialize(subscription:, timestamp:)
      @subscription = subscription
      @timestamp = timestamp

      super(nil)
    end

    def create
      invoice = Invoice.find_or_create_by!(
        subscription: subscription,
        from_date: from_date,
        to_date: to_date,
        issuing_date: issuing_date,
      )

      Fees::SubscriptionService.new(invoice).create

      compute_amounts(invoice)

      result.invoice = invoice
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :subscription, :timestamp

    delegate :plan, to: :subscription

    def from_date
      return @from_date if @from_date.present?

      @from_date = case subscription.plan.interval.to_sym
                   when :monthly
                     (Time.zone.at(timestamp) - 1.month).to_date
                   when :yearly
                     (Time.zone.at(timestamp) - 1.year).to_date
                   else
                     raise NotImplementedError
      end

      # NOTE: On first billing period, subscription might start after the computed start of period
      #       ei: if we bill on beginning of period, and user registered on the 15th, the invoice should
      #       start on the 15th (subscription date) and not on the 1st
      @from_date = subscription.started_at.to_date if from_date < subscription.started_at

      @from_date
    end

    def to_date
      return @to_date if @to_date.present?

      @to_date = (Time.zone.at(timestamp) - 1.day).to_date

      # NOTE: When price plan is configured as `pay_in_advance`, subscription creation will be
      #       billed immediatly. An invoice must be generated for it with only the subscription fee.
      #       The invoicing period will be only one day: the subscription day
      @to_date = subscription.started_at.to_date if to_date < subscription.started_at

      @to_date
    end

    def issuing_date
      return @issuing_date if @issuing_date.present?

      # NOTE: When price plan is configured as `pay_in_advance`, we issue the invoice for the first day of
      #       the period, it's on the last day otherwise
      @issuing_date = to_date

      @issuing_date = Time.zone.at(timestamp).to_date if subscription.plan.pay_in_advance?

      @issuing_date
    end

    def compute_amounts(invoice)
      fee_amounts = invoice.fees.select(:amount_cents, :vat_amount_cents)

      invoice.amount_cents = fee_amounts.sum(&:amount_cents)
      invoice.amount_currency = plan.amount_currency
      invoice.vat_amount_cents = fee_amounts.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = plan.amount_currency

      invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
      invoice.total_amount_currency = plan.amount_currency

      invoice.save!
    end
  end
end
