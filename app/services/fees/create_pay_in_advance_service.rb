# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceService < BaseService
    def initialize(charge:, event:, estimate: false)
      @charge = charge
      @event = event
      @estimate = estimate

      super
    end

    def call
      fees = []

      ActiveRecord::Base.transaction do
        if charge.group_properties.blank?
          fees << create_fee(properties: charge.properties)
        else
          fees += create_group_properties_fees
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

    attr_reader :charge, :event, :estimate

    delegate :billable_metric, to: :charge
    delegate :subscription, :customer, to: :event

    def create_fee(properties:, group: nil)
      aggregation_result = aggregate(properties:, group:)
      result = apply_charge_model(aggregation_result:, properties:)

      fee = Fee.new(
        subscription: event.subscription,
        charge:,
        amount_cents: result.amount,
        amount_currency: subscription.plan.amount_currency,
        taxes_rate: customer.applicable_vat_rate,
        fee_type: :charge,
        invoiceable: charge,
        units: result.units,
        properties: boundaries,
        events_count: result.count,
        group_id: group&.id,
        pay_in_advance_event_id: event.id,
        payment_status: :pending,
        pay_in_advance: true,
      )
      fee.compute_vat
      fee.save! unless estimate

      fee
    end

    def create_group_properties_fees
      charge.group_properties.each_with_object([]) do |group_properties, fees|
        group = billable_metric.selectable_groups.find_by(id: group_properties.group_id)
        next unless event_linked_to?(group:)

        fees << create_fee(properties: group_properties.values, group:)
      end
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(
        subscription,
        Time.current,
        current_usage: true,
      )
    end

    def boundaries
      @boundaries ||= {
        from_datetime: date_service.from_datetime,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: date_service.charges_from_datetime,
        charges_to_datetime: date_service.charges_to_datetime,
        timestamp: Time.current,
      }
    end

    def aggregate(properties:, group:)
      aggregation_result = BillableMetrics::PayInAdvanceAggregationService.call(
        billable_metric:, boundaries:, group:, properties:, event:,
      )
      aggregation_result.raise_if_error!
      aggregation_result
    end

    def apply_charge_model(aggregation_result:, properties:)
      charge_model_result = Charges::ApplyPayInAdvanceChargeModelService.call(
        charge:, aggregation_result:, properties:,
      )
      charge_model_result.raise_if_error!
      charge_model_result
    end

    def event_linked_to?(group:)
      return match_group?(group) && match_group?(group.parent) if group.parent

      match_group?(group)
    end

    def match_group?(group)
      return false unless event.properties.key?(group.key.to_s)

      event.properties[group.key.to_s] == group.value
    end

    def deliver_webhooks
      return if estimate

      result.fees.each { |f| SendWebhookJob.perform_later('fee.pay_in_advance_created', f) }
    end
  end
end
