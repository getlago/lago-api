# frozen_string_literal: true

module PersistedEvents
  class CreateOrUpdateService < BaseService
    def initialize(event)
      @event = event

      super(nil)
    end

    def call
      result.persisted_event = case event_operation_type
                               when :add
                                 add_metric
                               when :remove
                                 remove_metric
      end

      result
    end

    def matching_billable_metric?
      matching_billable_metric&.recurring_count_agg?
    end

    private

    attr_accessor :event

    delegate :customer, :subscription, :organization, to: :event

    def event_operation_type
      event.properties['operation_type']&.to_sym
    end

    def add_metric
      # NOTE: if we add a persisted event removed on the same day,
      #       since the granularity is on day
      #       we just need to set the removed_at field back to nil to
      #       prevent wrong units count
      if persisted_removed_on_event_day.present?
        persisted_removed_on_event_day.update!(removed_at: nil)
      else
        PersistedEvent.create!(
          customer: customer,
          billable_metric: matching_billable_metric,
          external_subscription_id: subscription.external_id,
          external_id: event.properties[matching_billable_metric.field_name],
          properties: event.properties,
          added_at: event.timestamp,
        )
      end
    end

    def remove_metric
      metric = PersistedEvent.find_by(
        customer_id: customer.id,
        billable_metric_id: matching_billable_metric.id,
        external_subscription_id: subscription.external_id,
        external_id: event.properties[matching_billable_metric.field_name],
        removed_at: nil,
      )

      return if metric.blank?

      metric.update!(removed_at: event.timestamp)
      metric
    end

    def matching_billable_metric
      @matching_billable_metric ||= organization.billable_metrics.find_by(
        code: event.code,
      )
    end

    def persisted_removed_on_event_day
      @persisted_removed_on_event_day ||= PersistedEvent
        .where('DATE(removed_at) = ?', event.timestamp.to_date)
        .find_by(
          customer_id: customer.id,
          billable_metric_id: matching_billable_metric.id,
          external_subscription_id: subscription.external_id,
          external_id: event.properties[matching_billable_metric.field_name],
        )
    end
  end
end
