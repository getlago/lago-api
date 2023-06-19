# frozen_string_literal: true

module QuantifiedEvents
  class CreateOrUpdateService < BaseService
    def initialize(event)
      @event = event

      super(nil)
    end

    def call
      result.quantified_event = case event_operation_type
                               when :add
                                 add_metric
                               when :remove
                                 remove_metric
      end

      result
    end

    def matching_billable_metric?
      matching_billable_metric&.recurring_count_agg? || matching_billable_metric&.unique_count_agg?
    end

    private

    attr_accessor :event

    delegate :customer, :subscription, :organization, to: :event

    def event_operation_type
      operation_type = event.properties['operation_type']&.to_sym
      (operation_type.nil? && matching_billable_metric&.unique_count_agg?) ? :add : operation_type
    end

    def add_metric
      # NOTE: if we add a quantified event removed on the same day,
      #       since the granularity is on day
      #       we just need to set the removed_at field back to nil to
      #       prevent wrong units count
      if quantified_removed_on_event_day.present?
        quantified_removed_on_event_day.update!(removed_at: nil)
      else
        QuantifiedEvent.create!(
          customer:,
          billable_metric: matching_billable_metric,
          external_subscription_id: subscription.external_id,
          external_id: event.properties[matching_billable_metric.field_name],
          properties: event.properties,
          added_at: event.timestamp,
          event:,
        )
      end
    end

    def remove_metric
      metric = QuantifiedEvent.find_by(
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

    def quantified_removed_on_event_day
      @quantified_removed_on_event_day ||= QuantifiedEvent
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
