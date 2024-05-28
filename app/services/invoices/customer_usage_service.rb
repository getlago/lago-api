# frozen_string_literal: true

module Invoices
  class CustomerUsageService < BaseService
    # NOTE: customer_id can reference the lago id or the external id of the customer
    # NOTE: subscription_id can reference the lago id or the external id of the subscription
    def initialize(current_user, customer_id:, subscription_id:, organization_id: nil)
      super(current_user)

      if organization_id.present?
        @organization_id = organization_id
        @customer = Customer.find_by!(external_id: customer_id, organization_id:)
        @subscription = @customer&.active_subscriptions&.find_by(external_id: subscription_id)
      else
        customer(customer_id:)
        @subscription = @customer&.active_subscriptions&.find_by(id: subscription_id)
      end
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: 'customer')
    end

    def call
      return result.not_found_failure!(resource: 'customer') unless @customer
      return result.not_allowed_failure!(code: 'no_active_subscription') if subscription.blank?

      result.usage = compute_usage
      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :subscription

    delegate :plan, to: :subscription
    delegate :organization, to: :subscription

    # NOTE: Since computing customer usage could take some time as it as to
    #       loop over a lot of records in database, the result is stored in a cache store.
    #       - Each charge result is stored in its own fragmented cache
    #       - The cache expiration is set to the end of the billing period
    #       - Cache will be automatically cleared if a new event is sent for a specific charge
    def compute_usage
      @invoice = Invoice.new(
        organization: subscription.organization,
        customer: subscription.customer,
        issuing_date: boundaries[:issuing_date],
        currency: plan.amount_currency,
      )

      add_charge_fees
      compute_amounts

      format_usage
    end

    def customer(customer_id: nil)
      @customer ||= Customer.find_by(
        id: customer_id,
        organization_id: result.user.organization_ids,
      )
    end

    def add_charge_fees
      query = subscription.plan.charges.joins(:billable_metric)
        .includes(:taxes, billable_metric: :organization, filters: {values: :billable_metric_filter})
        .order(Arel.sql('lower(unaccent(billable_metrics.name)) ASC'))

      invoice.fees = Parallel.flat_map(query.all, in_threads: ENV['LAGO_PARALLEL_THREADS_COUNT']&.to_i || 1) do |charge|
        ActiveRecord::Base.connection_pool.with_connection do
          charge_usage(charge)
        end
      end
    end

    def charge_usage(charge)
      return charge_usage_without_cache(charge) if organization.clickhouse_aggregation?

      json = Rails.cache.fetch(charge_cache_key(charge), expires_in: charge_cache_expiration) do
        fees_result = Fees::ChargeService.new(
          invoice:, charge:, subscription:, boundaries:,
        ).current_usage

        fees_result.raise_if_error!

        fees_result.fees.to_json
      end

      JSON.parse(json).map { |j| Fee.new(j) }
    end

    def charge_usage_without_cache(charge)
      fees_result = Fees::ChargeService.new(
        invoice:, charge:, subscription:, boundaries:,
      ).current_usage

      fees_result.raise_if_error!

      fees_result.fees
    end

    def boundaries
      return @boundaries if @boundaries.present?

      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        Time.current,
        current_usage: true,
      )

      {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        issuing_date: date_service.next_end_of_period,
        charges_duration: date_service.charges_duration_in_days
      }
    end

    def compute_amounts
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)

      invoice.fees.each do |fee|
        taxes_result = Fees::ApplyTaxesService.call(fee:)
        taxes_result.raise_if_error!
      end

      taxes_result = Invoices::ApplyTaxesService.call(invoice:)
      taxes_result.raise_if_error!

      invoice.total_amount_cents = invoice.fees_amount_cents + invoice.taxes_amount_cents
    end

    def charge_cache_key(charge)
      Subscriptions::ChargeCacheService.new(subscription:, charge:).cache_key
    end

    def charge_cache_expiration
      (boundaries[:charges_to_datetime] - Time.current).to_i.seconds
    end

    def format_usage
      OpenStruct.new(
        from_datetime: boundaries[:charges_from_datetime].iso8601,
        to_datetime: boundaries[:charges_to_datetime].iso8601,
        issuing_date: invoice.issuing_date.iso8601,
        currency: invoice.currency,
        amount_cents: invoice.fees_amount_cents,
        total_amount_cents: invoice.total_amount_cents,
        taxes_amount_cents: invoice.taxes_amount_cents,
        fees: invoice.fees,
      )
    end
  end
end
