# frozen_string_literal: true

module TimebasedEvents
  class CreateOrUpdateService < BaseService
    def initialize(event)
      @event = event

      super(nil)
    end

    def call
      result.timebased_event = case event_operation_type
                               when :add
                                 add_event
                               when :remove
                                 remove_event
      end

      result
    end

    def process_event?
      matching_charge.present? && block_time_present_and_elapsed?
    end

    def matching_billable_metric?
      matching_billable_metric&.usage_time_agg?
    end

    private

    attr_accessor :event

    delegate :subscription, :organization, to: :event

    def block_time_present_and_elapsed?
      diff_in_seconds = event.timestamp.to_i - latest_timebased_event_timestamp
      block_time_in_seconds = matching_charge.properties['block_time_in_minutes'] * 60
      diff_in_seconds.positive? && block_time_in_seconds.present? && diff_in_seconds >= block_time_in_seconds
    end

    def latest_timebased_event
      @latest_timebased_event ||= TimebasedEvent
        .where(organization_id: organization.id)
        .where(external_subscription_id: subscription.external_id)
        .where(event_type: TimebasedEvent.event_types[:usage_time_started])
        .where('timestamp <= ?', event.timestamp)
        .order(timestamp: :desc)
        .first
    end

    def latest_timebased_event_timestamp
      return 0 unless latest_timebased_event

      latest_timebased_event&.timestamp.to_i || 0
    end

    def plan
      @plan ||= subscription.plan
    end

    def matching_charge
      @matching_charge ||= Charge.find_by(
        plan_id: plan.id,
        billable_metric_id: matching_billable_metric.id,
        pay_in_advance: true,
        charge_model: 'timebased',
      )
    end

    def event_operation_type
      operation_type = event.properties['operation_type']&.to_sym
      operation_type.nil? ? :add : operation_type
    end

    def add_event
      TimebasedEvent.create!(
        organization:,
        external_customer_id: event.external_customer_id,
        external_subscription_id: event.external_subscription_id,
        billable_metric_id: matching_billable_metric.id,
        metadata: event.metadata,
        timestamp: Time.zone.at(event.timestamp),
        event_type: TimebasedEvent.event_types[:usage_time_started],
      )
    end

    def remove_event
      TimebasedEvent.find_by(
        organization:,
        external_customer_id: event.external_customer_id,
        external_subscription_id: event.external_subscription_id,
        billable_metric_id: matching_billable_metric.id,
        timestamp: Time.zone.at(event.timestamp),
        event_type: TimebasedEvent.event_types[:usage_time_started],
      )&.destroy
    end

    def matching_billable_metric
      @matching_billable_metric ||= organization.billable_metrics.find_by(
        code: event.code,
      )
    end
  end
end