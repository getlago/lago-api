# frozen_string_literal: true

module Invoices
  class CustomerUsageService < BaseService
    # NOTE: customer_id can reference the lago id or the external id of the customer
    # NOTE: subscription_id can reference the lago id or the external id of the subscription
    def initialize(current_user, customer_id:, subscription_id:, organization_id: nil)
      super(current_user)

      if organization_id.present?
        @organization_id = organization_id
        @customer = Customer.find_by!(external_id: customer_id, organization_id: organization_id)
        @subscription = @customer&.active_subscriptions&.find_by(external_id: subscription_id)
      else
        customer(customer_id: customer_id)
        @subscription = @customer&.active_subscriptions&.find_by(id: subscription_id)
      end
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: 'customer')
    end

    def usage
      return result.not_found_failure!(resource: 'customer') unless @customer
      return result.not_allowed_failure!(code: 'no_active_subscription') if subscription.blank?

      result.usage = JSON.parse(compute_usage, object_class: OpenStruct)
      result
    end

    # NOTE: Since computing customer usage could take some time as it as to
    #       loop over a lot of records in database, the result is stored in a cache store.
    #       - The cache expiration is at most, the end date of the billing period
    #         + 1 day to handle cache generated on the last billing period
    #       - The cache key includes the customer id and the creation date of the last customer event
    def compute_usage
      Rails.cache.fetch(cache_key, expires_in: cache_expiration.days) do
        @invoice = Invoice.new(
          customer: subscription.customer,
          issuing_date: boundaries[:issuing_date],
          amount_currency: plan.amount_currency,
          vat_amount_currency: plan.amount_currency,
          total_amount_currency: plan.amount_currency,
        )

        add_charge_fees
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

    def add_charge_fees
      query = subscription.plan.charges.joins(:billable_metric)
        .order(Arel.sql('lower(unaccent(billable_metrics.name)) ASC'))

      query.each do |charge|
        fees_result = Fees::ChargeService.new(
          invoice: invoice,
          charge: charge,
          subscription: subscription,
          boundaries: boundaries,
        ).current_usage

        fees_result.throw_error unless fees_result.success?

        invoice.fees << fees_result.fees
      end
    end

    def boundaries
      return @boundaries if @boundaries.present?

      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        Time.zone.now.to_date,
        current_usage: true,
      )

      {
        from_date: date_service.from_date,
        to_date: date_service.to_date,
        charges_from_date: date_service.charges_from_date,
        charges_to_date: date_service.charges_to_date,
        issuing_date: date_service.next_end_of_period(Time.zone.now),
      }
    end

    def compute_amounts
      invoice.amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.vat_amount_cents = invoice.fees.sum(&:vat_amount_cents)
      invoice.total_amount_cents = invoice.amount_cents + invoice.vat_amount_cents
    end

    def cache_key
      return @cache_key if @cache_key

      last_events = subscription.events.order(created_at: :desc).first(2).pluck(:created_at)
      expire_cache(last_events[1]) if last_events.count > 1
      last_created_at = last_events.first || subscription.created_at

      @cache_key = "current_usage/#{subscription.id}-#{last_created_at.iso8601}/#{plan.updated_at.iso8601}"
    end

    def expire_cache(date)
      Rails.cache.delete("current_usage/#{subscription.id}-#{date.iso8601}/#{plan.updated_at.iso8601}")
    end

    def cache_expiration
      expiration = (boundaries[:charges_to_date] - Time.zone.today).to_i + 1
      return 1 if expiration < 1
      return 4 if expiration > 4

      expiration
    end

    def format_usage
      {
        from_date: boundaries[:charges_from_date].iso8601,
        to_date: boundaries[:charges_to_date].iso8601,
        issuing_date: invoice.issuing_date.iso8601,
        amount_cents: invoice.amount_cents,
        amount_currency: invoice.amount_currency,
        total_amount_cents: invoice.total_amount_cents,
        total_amount_currency: invoice.total_amount_currency,
        vat_amount_cents: invoice.vat_amount_cents,
        vat_amount_currency: invoice.vat_amount_currency,
        fees: invoice.fees.group_by(&:charge_id).map do |charge_id, fees|
          fee = fees.first
          {
            units: fees.sum(&:units),
            amount_cents: fees.sum(&:amount_cents),
            amount_currency: fee.amount_currency,
            charge: {
              id: charge_id,
              charge_model: fee.charge.charge_model,
            },
            billable_metric: {
              id: fee.billable_metric.id,
              name: fee.billable_metric.name,
              code: fee.billable_metric.code,
              aggregation_type: fee.billable_metric.aggregation_type,
            },
            groups: fees.map do |f|
              next unless f.group

              {
                id: f.group.id,
                key: f.group.parent&.value,
                value: f.group.value,
                units: f.units,
                amount_cents: f.amount_cents,
              }
            end.compact,
          }
        end,
      }.to_json
    end
  end
end
