# frozen_string_literal: true

module Invoices
  class CustomerUsageService < BaseService
    def initialize(customer:, subscription:, timestamp: Time.current, apply_taxes: true, with_cache: true, max_to_datetime: nil)
      super

      @apply_taxes = apply_taxes
      @customer = customer
      @subscription = subscription
      @timestamp = timestamp # To not set this value if without disabling the cache
      @with_cache = with_cache

      # NOTE: used to force charges_to_datetime boundary
      @max_to_datetime = max_to_datetime
    end

    def self.with_external_ids(customer_external_id:, external_subscription_id:, organization_id:, apply_taxes: true)
      customer = Customer.find_by!(external_id: customer_external_id, organization_id:)
      subscription = customer&.active_subscriptions&.find_by(external_id: external_subscription_id)
      new(customer:, subscription:, apply_taxes:)
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "customer")
    end

    def self.with_ids(organization_id:, customer_id:, subscription_id:, apply_taxes: true)
      customer = Customer.find_by(id: customer_id, organization_id:)
      subscription = customer&.active_subscriptions&.find_by(id: subscription_id)
      new(customer:, subscription:, apply_taxes:)
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "customer")
    end

    def call
      return result.not_found_failure!(resource: "customer") unless @customer
      return result.not_allowed_failure!(code: "no_active_subscription") if subscription.blank?

      result.usage = compute_usage
      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :subscription, :timestamp, :apply_taxes, :with_cache, :max_to_datetime
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
        currency: plan.amount_currency
      )

      add_charge_fees

      if apply_taxes && customer_provider_taxation?
        compute_amounts_with_provider_taxes
      elsif apply_taxes
        compute_amounts
      else
        compute_amounts_without_tax
      end

      format_usage
    end

    def add_charge_fees
      query = subscription.plan.charges.joins(:billable_metric)
        .includes(:taxes, billable_metric: :organization, filters: {values: :billable_metric_filter})
        .order(Arel.sql("lower(unaccent(billable_metrics.name)) ASC"))

      # we're capturing the context here so we can re-use inside the threads. This will correctly propagate spans to this current span
      context = OpenTelemetry::Context.current

      invoice.fees = Parallel.flat_map(query.all, in_threads: ENV["LAGO_PARALLEL_THREADS_COUNT"]&.to_i || 0) do |charge|
        OpenTelemetry::Context.with_current(context) do
          ActiveRecord::Base.connection_pool.with_connection do
            charge_usage(charge)
          end
        end
      end
    end

    def charge_usage(charge)
      cache_middleware = Subscriptions::ChargeCacheMiddleware.new(
        subscription:,
        charge:,
        to_datetime: boundaries[:charges_to_datetime],
        # NOTE: Will be turned on for clickhouse in the future
        cache: organization.clickhouse_events_store? ? false : with_cache
      )

      applied_boundaries = boundaries
      applied_boundaries = applied_boundaries.merge(charges_to_datetime: max_to_datetime) if max_to_datetime

      Fees::ChargeService
        .call(invoice:, charge:, subscription:, boundaries: applied_boundaries, current_usage: true, cache_middleware:)
        .raise_if_error!
        .fees
    end

    def boundaries
      return @boundaries if @boundaries.present?

      date_service = Subscriptions::DatesService.new_instance(
        subscription,
        timestamp,
        current_usage: true
      )

      @boundaries = {
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

    def compute_amounts_without_tax
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.taxes_amount_cents = 0
      invoice.taxes_rate = 0
      invoice.total_amount_cents = invoice.fees_amount_cents
    end

    def compute_amounts_with_provider_taxes
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)

      taxes_result = Rails.cache.read(provider_taxes_cache_key)

      unless taxes_result
        # Call the service if the cache is empty
        taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateDraftService.call(invoice:, fees: invoice.fees)

        # Cache the result only if it's successful
        Rails.cache.write(provider_taxes_cache_key, taxes_result, expires_in: 24.hours) if taxes_result.success?
      end

      return result.validation_failure!(errors: {tax_error: [taxes_result.error.code]}) unless taxes_result.success?

      result.fees_taxes = taxes_result.fees

      invoice.fees.each do |fee|
        fee_taxes = result.fees_taxes.find { |item| item.item_id == fee.id }

        res = Fees::ApplyProviderTaxesService.call(fee:, fee_taxes:)
        res.raise_if_error!
      end

      res = Invoices::ApplyProviderTaxesService.call(invoice:, provider_taxes: result.fees_taxes)
      res.raise_if_error!

      invoice.total_amount_cents = invoice.fees_amount_cents + invoice.taxes_amount_cents
    end

    def provider_taxes_cache_key
      [
        "provider-taxes",
        subscription.id,
        plan.updated_at.iso8601
      ].join("/")
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
        fees: invoice.fees
      )
    end

    def customer_provider_taxation?
      @customer_provider_taxation ||= invoice.customer.anrok_customer
    end
  end
end
