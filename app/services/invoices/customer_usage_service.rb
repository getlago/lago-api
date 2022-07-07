# frozen_string_literal: true

module Invoices
  class CustomerUsageService < BaseService
    def initialize(current_user, customer_id:)
      super(current_user)

      customer(customer_id: customer_id)
    end

    def usage
      return result.fail!('not_found') unless customer
      return result.fail!('no_active_subscription') if subscription.blank?

      invoice = Invoice.new(
        subscription: subscription,
        charges_from_date: charges_from_date,
        from_date: from_date,
        to_date: to_date,
        issuing_date: issuing_date,
      )

      result.invoice = invoice

      add_charge_fee
      compute_amounts

      result
    end

    private

    delegate :invoice, to: :result
    delegate :plan, to: :subscription

    def customer(customer_id: nil)
      @customer ||= Customer.find_by(
        id: customer_id,
        organization_id: result.user.organization_ids,
      )
    end

    def subscription
      @subscription ||= customer.active_subscription
    end

    def from_date
      return @from_date if @from_date.present?

      @from_date = case subscription.plan.interval.to_sym
                   when :weekly
                     Time.zone.today.beginning_of_week
                   when :monthly
                     Time.zone.today.beginning_of_month
                   when :yearly
                     Time.zone.today.beginning_of_year
                   else
                     raise NotImplementedError
      end

      # NOTE: On first billing period, subscription might start after the computed start of period
      #       ei: if we bill on beginning of period, and user registered on the 15th, the usage should
      #       start on the 15th (subscription date) and not on the 1st
      @from_date = subscription.started_at.to_date if @from_date < subscription.started_at

      @from_date
    end

    def charges_from_date
      return @charges_from_date if @charges_from_date.present?

      @charges_from_date = if subscription.plan.yearly? && subscription.plan.bill_charges_monthly
        Time.zone.today.beginning_of_month
      else
        from_date
      end

      @charges_from_date = subscription.started_at.to_date if @charges_from_date < subscription.started_at

      @charges_from_date
    end

    def to_date
      return @to_date if @to_date.present?

      @to_date = case subscription.plan.interval.to_sym
                 when :weekly
                   Time.zone.today.end_of_week
                 when :monthly
                   Time.zone.today.end_of_month
                 when :yearly
                   if subscription.plan.bill_charges_monthly
                     Time.zone.today.end_of_month
                   else
                     Time.zone.today.end_of_year
                   end
                 else
                   raise NotImplementedError
      end

      @to_date
    end

    def issuing_date
      return @issuing_date if @issuing_date.present?

      # NOTE: When price plan is configured as `pay_in_advance`, we issue the invoice for the first day of
      #       the period, it's on the last day otherwise
      @issuing_date = to_date
      @issuing_date = to_date + 1.day if subscription.plan.pay_in_advance?
      @issuing_date
    end

    def add_charge_fee
      subscription.plan.charges.each do |charge|
        fee_result = Fees::ChargeService.new(
          invoice: invoice,
          charge: charge,
        ).current_usage

        fee_result.throw_error unless fee_result.success?

        invoice.fees << fee_result.fee
      end
    end

    def compute_amounts
      invoice.amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.amount_currency = plan.amount_currency
      invoice.vat_amount_cents = invoice.fees.sum(&:vat_amount_cents)
      invoice.vat_amount_currency = plan.amount_currency
      invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
      invoice.total_amount_currency = plan.amount_currency
    end
  end
end
