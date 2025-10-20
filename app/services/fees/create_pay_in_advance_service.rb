# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceService < BaseService
    Result = BaseResult[:fees, :fees_taxes, :invoice_id]

    def initialize(charge:, event:, billing_at: nil, estimate: false)
      @charge = charge
      @event = Events::CommonFactory.new_instance(source: event)
      @billing_at = billing_at || @event.timestamp
      @estimate = estimate

      super
    end

    def call
      fees = []

      ActiveRecord::Base.transaction(**isolation_mode) do
        fees << if charge.filters.any?
          init_charge_filter_fee
        else
          init_fee(properties:)
        end
      end

      ActiveRecord::Base.transaction do
        result.fees = persist_fees(fees.compact)

        if customer_provider_taxation?
          fee_taxes_result = apply_provider_taxes(fees)

          unless fee_taxes_result.success?
            result.validation_failure!(errors: {tax_error: [fee_taxes_result.error.code]})
            result.raise_if_error! unless charge.invoiceable?

            return result # rubocop:disable Rails/TransactionExitStatement
          end
        end
      end

      deliver_webhooks

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :charge, :event, :billing_at, :estimate

    delegate :billable_metric, to: :charge
    delegate :subscription, to: :event

    def filter
      @filter ||= ChargeFilters::EventMatchingService.call(charge:, event:).charge_filter
    end

    def init_fee(properties:, charge_filter: nil)
      aggregation_result = aggregate(properties:, charge_filter:)

      cache_aggregation_result(aggregation_result:, charge_filter:)

      charge_model_result = apply_charge_model(aggregation_result:, properties:)

      if charge.applied_pricing_unit
        pricing_unit_usage = PricingUnitUsage.build_from_fiat_amounts(
          amount: charge_model_result.amount / charge.pricing_unit.subunit_to_unit.to_d,
          unit_amount: charge_model_result.unit_amount,
          applied_pricing_unit: charge.applied_pricing_unit
        )

        amount_cents, precise_amount_cents, unit_amount_cents, precise_unit_amount = pricing_unit_usage
          .to_fiat_currency_cents(subscription.plan.amount.currency)
          .values_at(:amount_cents, :precise_amount_cents, :unit_amount_cents, :precise_unit_amount)
      else
        pricing_unit_usage = nil
        amount_cents = charge_model_result.amount
        precise_amount_cents = charge_model_result.precise_amount
        unit_amount_cents = charge_model_result.unit_amount * subscription.plan.amount.currency.subunit_to_unit
        precise_unit_amount = charge_model_result.unit_amount
      end

      Fee.new(
        subscription:,
        charge:,
        organization_id: customer.organization_id,
        billing_entity_id: customer.billing_entity_id,
        amount_cents:,
        precise_amount_cents:,
        amount_currency: subscription.plan.amount_currency,
        fee_type: :charge,
        invoiceable: charge,
        units: charge_model_result.units,
        total_aggregated_units: charge_model_result.units,
        properties: boundaries.to_h,
        events_count: charge_model_result.count,
        charge_filter_id: charge_filter&.id,
        pay_in_advance_event_id: event.id,
        pay_in_advance_event_transaction_id: event.transaction_id,
        payment_status: :pending,
        pay_in_advance: true,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        unit_amount_cents:,
        precise_unit_amount:,
        grouped_by: format_grouped_by,
        amount_details: charge_model_result.amount_details || {},
        pricing_unit_usage:
      )
    end

    def init_charge_filter_fee
      init_fee(properties:, charge_filter: filter || ChargeFilter.new(charge:))
    end

    def persist_fees(fees)
      fees.map do |fee|
        unless customer_provider_taxation?
          taxes_result = Fees::ApplyTaxesService.call(fee:)
          taxes_result.raise_if_error!
        end

        fee.save! unless estimate
        fee
      end
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        billing_at,
        current_usage: true
      )
    end

    def properties
      @properties ||= filter&.properties || charge.properties
    end

    def boundaries
      @boundaries ||= BillingPeriodBoundaries.new(
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        charges_duration: date_service.charges_duration_in_days,
        timestamp: billing_at
      )
    end

    def aggregate(properties:, charge_filter: nil)
      aggregation_result = Charges::PayInAdvanceAggregationService.call(
        charge:, boundaries:, properties:, event:, charge_filter:
      )
      aggregation_result.raise_if_error!
      aggregation_result
    end

    def apply_charge_model(aggregation_result:, properties:)
      charge_model_result = Charges::ApplyPayInAdvanceChargeModelService.call(
        charge:, aggregation_result:, properties:
      )
      charge_model_result.raise_if_error!
      charge_model_result
    end

    def deliver_webhooks
      return if estimate

      result.fees.each { |f| SendWebhookJob.perform_later("fee.created", f) }
    end

    def cache_aggregation_result(aggregation_result:, charge_filter:)
      return unless aggregation_result.current_aggregation.present? ||
        aggregation_result.max_aggregation.present? ||
        aggregation_result.max_aggregation_with_proration.present?

      CachedAggregation.create!(
        organization_id: event.organization_id,
        event_transaction_id: event.transaction_id,
        timestamp: billing_at,
        external_subscription_id: event.external_subscription_id,
        charge_id: charge.id,
        charge_filter_id: charge_filter&.id,
        current_aggregation: aggregation_result.current_aggregation,
        current_amount: aggregation_result.current_amount,
        max_aggregation: aggregation_result.max_aggregation,
        max_aggregation_with_proration: aggregation_result.max_aggregation_with_proration,
        grouped_by: format_grouped_by
      )
    end

    def format_grouped_by
      return {} if properties["grouped_by"].blank?

      properties["grouped_by"].index_with { event.properties[it] }
    end

    def customer_provider_taxation?
      @apply_provider_taxes ||= integration_customer.present?
    end

    def integration_customer
      @integration_customer ||= customer.tax_customer
    end

    def customer
      @customer ||= subscription.customer
    end

    def apply_provider_taxes(fees_result)
      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateService.call(invoice:, fees: fees_result)

      return taxes_result unless taxes_result.success?

      result.fees_taxes = taxes_result.fees

      fees_result.each do |fee|
        item_id = fee.id || fee.item_id
        fee_taxes = result.fees_taxes.find { |item| item.item_id == item_id }

        res = Fees::ApplyProviderTaxesService.call(fee:, fee_taxes:)
        res.raise_if_error!
      end

      taxes_result
    end

    FakeInvoice = Data.define(:id, :issuing_date, :currency, :customer)

    def invoice
      result.invoice_id = SecureRandom.uuid

      FakeInvoice.new(
        id: result.invoice_id,
        issuing_date: Time.current.in_time_zone(customer.applicable_timezone).to_date,
        currency: subscription.plan.amount_currency,
        customer:
      )
    end

    def isolation_mode
      # NOTE: this is only to avoid failure with spec scnearios
      return {} if ActiveRecord::Base.connection.transaction_open?

      {isolation: :repeatable_read}
    end
  end
end
