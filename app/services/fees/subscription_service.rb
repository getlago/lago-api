# frozen_string_literal: true

module Fees
  class SubscriptionService < BaseService

    def initialize(invoice)
      @invoice = invoice
      super(nil)
    end

    def create
      return result if already_billed?

      new_amount_cents = compute_amount
      
      new_fee = Fee.new(
        invoice: invoice,
        subscription: subscription,
        amount_cents: new_amount_cents,
        amount_currency: plan.amount_currency,
        vat_rate: plan.vat_rate,
      )

      new_fee.compute_vat
      new_fee.save!

      result.fee = new_fee
      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_accessor :invoice
    delegate :plan, :subscription, to: :invoice

    def compute_amount
      return plan.amount_cents unless plan.beginning_of_period?
      return plan.amount_cents unless plan.pro_rata?
      return plan.amount_cents if invoice.subscription.fees.subscription_kind.exists?

      from_date = invoice.from_date
      to_date = invoice.to_date

      # NOTE: Number of days of the first period since subscription creation
      days_to_bill = (from_date - invoice.to_date).to_i

      # NOTE: cost of a single day in the period
      day_price = plan.amount_cents.to_f / period_duration

      (days_to_bill * day_price).to_i
    end

    # NOTE: Returns number of days of the invoice period
    def period_duration
      case plan.frequency.to_sym
      when :monthly
        (invoice.to_date.beginning_of_month) - invoice.to_date
      when :yearly
        (invoice.to_date.beginning_of_year) - invoice.to_date
      else
        raise NotImplementedError
      end
    end

    def already_billed?
      existing_fee = invoice.fees.subscription_kind.first
      return false unless existing_fee
        
      result.fee = existing_fee
      true
    end
  end
end
