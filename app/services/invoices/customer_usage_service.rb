# frozen_string_literal: true

module Invoices
  class CustomerUsageService < BaseService
    def initialize(
      customer:,
      subscription:,
      timestamp: Time.current,
      apply_taxes: true,
      with_cache: true,
      max_timestamp: nil,
      calculate_projected_usage: false,
      with_zero_units_filters: true
    )
      super

      @apply_taxes = apply_taxes
      @customer = customer
      @subscription = subscription
      @timestamp = timestamp # To not set this value if without disabling the cache
      @with_cache = with_cache
      @calculate_projected_usage = calculate_projected_usage
      @with_zero_units_filters = with_zero_units_filters

      # NOTE: used to force charges_to_datetime boundary
      @max_timestamp = max_timestamp
    end

    def self.with_external_ids(customer_external_id:, external_subscription_id:, organization_id:, apply_taxes: true, calculate_projected_usage: false)
      customer = Customer.find_by!(external_id: customer_external_id, organization_id:)
      subscription = customer&.active_subscriptions&.find_by(external_id: external_subscription_id)
      new(customer:, subscription:, apply_taxes:, calculate_projected_usage:)
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "customer")
    end

    def self.with_ids(organization_id:, customer_id:, subscription_id:, apply_taxes: true, calculate_projected_usage: false)
      customer = Customer.find_by(id: customer_id, organization_id:)
      subscription = customer&.active_subscriptions&.find_by(id: subscription_id)
      new(customer:, subscription:, apply_taxes:, calculate_projected_usage:)
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "customer")
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_allowed_failure!(code: "no_active_subscription") if subscription.blank?

      result.usage = compute_usage
      result.invoice = invoice
      result
    rescue BaseService::ThrottlingError => error
      result.too_many_provider_requests_failure!(provider_name: error.provider_name, error:)
    end

    private

    attr_reader :customer, :invoice, :subscription, :timestamp, :apply_taxes, :with_cache, :max_timestamp, :calculate_projected_usage, :with_zero_units_filters

    delegate :plan, to: :subscription
    delegate :organization, to: :subscription
    delegate :billing_entity, to: :customer

    # NOTE: Since computing customer usage could take some time as it as to
    #       loop over a lot of records in database, the result is stored in a cache store.
    #       - Each charge result is stored in its own fragmented cache
    #       - The cache expiration is set to the end of the billing period
    #       - Cache will be automatically cleared if a new event is sent for a specific charge
    def compute_usage
      @invoice = Invoice.new(
        organization:,
        billing_entity:,
        customer:,
        issuing_date: boundaries.issuing_date,
        currency: plan.amount_currency
      )

      invoice.fees = compute_charge_fees

      if apply_taxes && customer_provider_taxation?
        compute_amounts_with_provider_taxes
      elsif apply_taxes
        compute_amounts
      else
        compute_amounts_without_tax
      end

      format_usage
    end

    def compute_charge_fees
      fees = []

      received_event_codes = distinct_event_codes(subscription, boundaries)

      subscription
        .plan
        .charges
        .joins(:billable_metric)
        .includes(:taxes, billable_metric: :organization, filters: {values: :billable_metric_filter})
        .find_each do |charge|
        bypass_aggregation = !received_event_codes.include?(charge.billable_metric.code)
        fees += charge_usage(charge, bypass_aggregation)
      end

      fees.sort_by { |f| f.billable_metric.name.downcase }
    end

    def charge_usage(charge, bypass_aggregation)
      cache_middleware = Subscriptions::ChargeCacheMiddleware.new(
        subscription:,
        charge:,
        to_datetime: boundaries.charges_to_datetime,
        cache: with_cache
      )

      applied_boundaries = boundaries
      applied_boundaries = boundaries.dup.tap { it.max_timestamp = max_timestamp } if max_timestamp

      Fees::ChargeService
        .call(
          invoice:,
          charge:,
          subscription:,
          boundaries: applied_boundaries,
          context: :current_usage,
          cache_middleware:,
          calculate_projected_usage:,
          with_zero_units_filters:,
          bypass_aggregation:
        )
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

      @boundaries = BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        issuing_date: date_service.next_end_of_period,
        charges_duration: date_service.charges_duration_in_days,
        timestamp:
      )
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

      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateDraftService.call(invoice:, fees: invoice.fees)

      return result.validation_failure!(errors: {tax_error: [taxes_result.error.code]}) unless taxes_result.success?

      result.fees_taxes = taxes_result.fees

      invoice.fees.each do |fee|
        fee_taxes = result.fees_taxes.find do |item|
          item.item_key == fee.item_key
        end

        res = Fees::ApplyProviderTaxesService.call(fee:, fee_taxes:)
        res.raise_if_error!
      end

      res = Invoices::ApplyProviderTaxesService.call(invoice:, provider_taxes: result.fees_taxes)
      res.raise_if_error!

      invoice.total_amount_cents = invoice.fees_amount_cents + invoice.taxes_amount_cents
    end

    def format_usage
      SubscriptionUsage.new(
        from_datetime: boundaries.charges_from_datetime.iso8601,
        to_datetime: boundaries.charges_to_datetime.iso8601,
        issuing_date: invoice.issuing_date.iso8601,
        currency: invoice.currency,
        amount_cents: invoice.fees_amount_cents,
        total_amount_cents: invoice.total_amount_cents,
        taxes_amount_cents: invoice.taxes_amount_cents,
        fees: invoice.fees
      )
    end

    def customer_provider_taxation?
      @customer_provider_taxation ||= invoice.customer.tax_customer
    end

    def distinct_event_codes(subscription, boundaries)
      Events::Stores::StoreFactory.new_instance(
        organization: subscription.organization,
        current_usage: true,
        subscription:,
        boundaries: {
          from_datetime: boundaries.charges_from_datetime,
          to_datetime: boundaries.charges_to_datetime
        }
      ).distinct_codes
    end
  end
end
