# frozen_string_literal: true

module Events
  class EnrichService < BaseService
    Result = BaseResult[:enriched_events]

    def initialize(event:, subscription:, billable_metric:, charges:)
      @event = event
      @subscription = subscription
      @billable_metric = billable_metric
      @charges = charges

      super
    end

    def call
      enriched_event = init_enriched_event

      EnrichedEvent.transaction do
        result.enriched_events = charges.map do |charge|
          ev = enriched_event.dup
          ev.charge_id = charge.id

          charge_filter = ChargeFilters::EventMatchingService.call(charge:, event:).charge_filter
          ev.charge_filter_id = charge_filter&.id
          ev.grouped_by = format_grouped_by(charge_filter&.pricing_group_keys.presence || charge.pricing_group_keys)
          ev.save!
          ev
        end
      end

      result
    end

    private

    attr_reader :event, :subscription, :billable_metric, :charges

    def init_enriched_event
      enriched_event = EnrichedEvent.new
      enriched_event.event_id = event.id
      enriched_event.organization_id = event.organization_id
      enriched_event.code = event.code
      enriched_event.transaction_id = event.transaction_id
      enriched_event.timestamp = event.timestamp

      enriched_event.external_subscription_id = subscription.external_id
      enriched_event.subscription_id = subscription.id
      enriched_event.plan_id = subscription.plan_id

      enriched_event.properties = event.properties
      enriched_event.enriched_at = Time.current
      enriched_event.value = (event.properties || {})[billable_metric.field_name] || 0
      enriched_event.value = 1 if billable_metric.count_agg?
      enriched_event.decimal_value = decimal_value(enriched_event.value)
      enriched_event
    end

    def format_grouped_by(pricing_group_keys)
      return {} if pricing_group_keys.blank?

      pricing_group_keys.sort.index_with { event.properties[it] }
    end

    def decimal_value(value)
      BigDecimal(value.to_s)
    rescue ArgumentError
      BigDecimal(0)
    end
  end
end
