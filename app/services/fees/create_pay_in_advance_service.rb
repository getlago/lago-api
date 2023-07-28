# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceService < BaseService
    def initialize(charge:, event:, estimate: false, invoice: nil)
      @charge = charge
      @event = event
      @estimate = estimate
      @invoice = invoice

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

    attr_reader :charge, :event, :estimate, :invoice

    delegate :billable_metric, to: :charge
    delegate :subscription, :customer, to: :event

    def create_fee(properties:, group: nil)
      ActiveRecord::Base.transaction do
        aggregation_result = aggregate(properties:, group:)

        update_event_metadata(aggregation_result:)

        result = apply_charge_model(aggregation_result:, properties:)

        fee = Fee.new(
          invoice:,
          subscription: event.subscription,
          charge:,
          amount_cents: result.amount,
          amount_currency: subscription.plan.amount_currency,
          fee_type: :charge,
          invoiceable: charge,
          units: result.units,
          properties: boundaries,
          events_count: result.count,
          group_id: group&.id,
          pay_in_advance_event_id: event.id,
          payment_status: :pending,
          pay_in_advance: true,
          taxes_amount_cents: 0,
        )

        if estimate || invoice.nil?
          taxes_result = Fees::ApplyTaxesService.call(fee:)
          taxes_result.raise_if_error!
        end

        fee.save! unless estimate

        fee
      end
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
        event.timestamp,
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
      aggregation_result = Charges::PayInAdvanceAggregationService.call(
        charge:, boundaries:, group:, properties:, event:,
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

      result.fees.each { |f| SendWebhookJob.perform_later('fee.created', f) }
    end

    def update_event_metadata(aggregation_result:)
      unless aggregation_result.current_aggregation.nil?
        event.metadata['current_aggregation'] = aggregation_result.current_aggregation
      end

      unless aggregation_result.max_aggregation.nil?
        event.metadata['max_aggregation'] = aggregation_result.max_aggregation
      end

      unless aggregation_result.max_aggregation_with_proration.nil?
        event.metadata['max_aggregation_with_proration'] = aggregation_result.max_aggregation_with_proration
      end

      event.save!
    end
  end
end
