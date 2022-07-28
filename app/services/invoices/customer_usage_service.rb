# frozen_string_literal: true

module Invoices
  class CustomerUsageService < BaseService
    def initialize(current_user, customer_id:, subscription_id:, organization_id: nil)
      super(current_user)

      if organization_id.present?
        @organization_id = organization_id
        @customer = Customer.find_by(
          customer_id: customer_id,
          organization_id: organization_id,
        )
      else
        customer(customer_id: customer_id)
      end

      @subscription = find_subscription(subscription_id)
    end

    def usage
      return result.fail!('not_found') unless @customer
      return result.fail!('no_active_subscription') if subscription.blank?

      result.usage = JSON.parse(compute_usage, object_class: OpenStruct)
      result
    end

    # NOTE: Since computing customer usage could take some time as it as to
    #       loop over a lot of records in database, the result is stored in a cache store.
    #       - The cache expiration is at most, the end date of the billing period
    #         + 1 day to handle cache generated on the last billing period
    #       - The cache key includes the customer id and the creation date of the last customer event
    # TODO: Refresh cache automatically when receiving an new event
    def compute_usage
      Rails.cache.fetch(cache_key, expires_in: cache_expiration.days) do
        @invoice = Invoice.new(
          subscription: subscription,
          charges_from_date: charges_from_date,
          from_date: from_date,
          to_date: to_date,
          issuing_date: issuing_date,
        )

        add_charge_fee
        compute_amounts

        format_usage
      end
    end

    private

    attr_reader :invoice, :subscription

    delegate :plan, to: :subscription

    def customer(customer_id: nil)
      @customer ||= Customer.find_by(
        id: customer_id,
        organization_id: result.user.organization_ids,
      )
    end

    def find_subscription(subscription_id)
      customer&.active_subscriptions&.find_by(id: subscription_id)
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
      query = subscription.plan.charges.joins(:billable_metric)
        .order(Arel.sql('lower(unaccent(billable_metrics.name)) ASC'))

      query.each do |charge|
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

    def cache_key
      return @cache_key if @cache_key

      last_events = customer.events.order(created_at: :desc).first(2).pluck(:created_at)
      expire_cache(last_events[1]) if last_events.count > 1
      last_created_at = last_events.first || customer.created_at

      @cache_key = "current_usage/#{customer.id}-#{last_created_at.iso8601}/#{plan.updated_at.iso8601}"
    end

    def expire_cache(date)
      Rails.cache.delete("current_usage/#{customer.id}-#{date.iso8601}/#{plan.updated_at.iso8601}")
    end

    def cache_expiration
      expiration = (to_date - Time.zone.today).to_i + 1
      expiration > 4 ? 4 : expiration
    end

    def format_usage
      {
        from_date: invoice.charges_from_date.iso8601,
        to_date: invoice.to_date.iso8601,
        issuing_date: invoice.issuing_date.iso8601,
        amount_cents: invoice.amount_cents,
        amount_currency: invoice.amount_currency,
        total_amount_cents: invoice.total_amount_cents,
        total_amount_currency: invoice.total_amount_currency,
        vat_amount_cents: invoice.vat_amount_cents,
        vat_amount_currency: invoice.vat_amount_currency,
        fees: invoice.fees.map do |fee|
          {
            units: fee.units,
            amount_cents: fee.amount_cents,
            amount_currency: fee.amount_currency,
            charge: {
              id: fee.charge.id,
              charge_model: fee.charge.charge_model,
            },
            billable_metric: {
              id: fee.billable_metric.id,
              name: fee.billable_metric.name,
              code: fee.billable_metric.code,
              aggregation_type: fee.billable_metric.aggregation_type,
            },
          }
        end,
      }.to_json
    end
  end
end
