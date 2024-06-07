# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceService < BaseService
    def initialize(charge:, event:, billing_at: nil, estimate: false)
      @charge = charge
      @event = Events::CommonFactory.new_instance(source: event)
      @billing_at = billing_at || @event.timestamp
      @estimate = estimate

      super
    end

    def call
      fees = []

      ActiveRecord::Base.transaction do
        fees << if charge.filters.any?
          create_charge_filter_fee
        else
          create_fee(properties: charge.properties)
        end
      end

      result.fees = fees.compact
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

    def create_fee(properties:, charge_filter: nil)
      ActiveRecord::Base.transaction do
        aggregation_result = aggregate(properties:, charge_filter:)

        cache_aggregation_result(aggregation_result:, charge_filter:)

        result = apply_charge_model(aggregation_result:, properties:)
        unit_amount_cents = result.unit_amount * subscription.plan.amount.currency.subunit_to_unit

        fee = Fee.new(
          subscription:,
          charge:,
          amount_cents: result.amount,
          amount_currency: subscription.plan.amount_currency,
          fee_type: :charge,
          invoiceable: charge,
          units: result.units,
          total_aggregated_units: result.units,
          properties: boundaries,
          events_count: result.count,
          charge_filter_id: charge_filter&.id,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          payment_status: :pending,
          pay_in_advance: true,
          taxes_amount_cents: 0,
          unit_amount_cents:,
          precise_unit_amount: result.unit_amount,
          grouped_by: format_grouped_by
        )

        taxes_result = Fees::ApplyTaxesService.call(fee:)
        taxes_result.raise_if_error!

        fee.save! unless estimate

        fee
      end
    end

    def create_charge_filter_fee
      properties = charge.properties

      filter = ChargeFilters::EventMatchingService.call(charge:, event:).charge_filter
      properties = filter.properties if filter

      create_fee(properties:, charge_filter: filter || ChargeFilter.new(charge:))
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        billing_at,
        current_usage: true
      )
    end

    def boundaries
      @boundaries ||= {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        charges_duration: date_service.charges_duration_in_days,
        timestamp: billing_at
      }
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

      result.fees.each { |f| SendWebhookJob.perform_later('fee.created', f) }
    end

    def cache_aggregation_result(aggregation_result:, charge_filter:)
      return unless aggregation_result.current_aggregation.present? ||
        aggregation_result.max_aggregation.present? ||
        aggregation_result.max_aggregation_with_proration.present?

      CachedAggregation.create!(
        organization_id: event.organization_id,
        event_id: event.id,
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
      return {} if charge.properties['grouped_by'].blank?

      charge.properties['grouped_by'].index_with { event.properties[_1] }
    end
  end
end
