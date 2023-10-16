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

        cache_aggregation_result(aggregation_result:, group:)

        result = apply_charge_model(aggregation_result:, properties:)

        fee = Fee.new(
          invoice:,
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
      group_fees = []

      if billable_metric.selectable_groups.any?
        # NOTE: Create a fee for each groups defined on the charge.
        charge.group_properties.each do |group_properties|
          group = billable_metric.selectable_groups.find_by(id: group_properties.group_id)
          next unless event_linked_to?(group:)

          group_fees << create_fee(properties: group_properties.values, group:)
        end

        # NOTE: Create a fee for groups not defined (with default properties).
        billable_metric.selectable_groups.where.not(id: charge.group_properties.pluck(:group_id)).each do |group|
          next unless event_linked_to?(group:)

          group_fees << create_fee(properties: charge.properties, group:)
        end
      else
        group_fees << create_fee(properties: charge.properties)
      end

      group_fees
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

    def cache_aggregation_result(aggregation_result:, group:)
      return unless aggregation_result.current_aggregation.present? ||
                    aggregation_result.max_aggregation.present? ||
                    aggregation_result.max_aggregation_with_proration

      CachedAggregation.create!(
        organization_id: event.organization_id,
        event_id: event.id,
        timestamp: event.timestamp,
        external_subscription_id: event.external_subscription_id,
        charge_id: charge.id,
        group_id: group&.id,
        current_aggregation: aggregation_result.current_aggregation,
        max_aggregation: aggregation_result.max_aggregation,
        max_aggregation_with_proration: aggregation_result.max_aggregation_with_proration,
      )
    end
  end
end
