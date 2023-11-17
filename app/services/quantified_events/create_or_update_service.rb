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

    def process_event?
      return true unless event_operation_type == :add
      return true unless matching_billable_metric&.unique_count_agg?

      # NOTE: Ensure no active quantified metric exists with the same external id
      QuantifiedEvent.where(
        organization_id: organization.id,
        billable_metric_id: matching_billable_metric.id,
        external_id: event.properties[matching_billable_metric.field_name],
        external_subscription_id: subscription.external_id,
      ).where(removed_at: nil).none?
    end

    private

    attr_accessor :event

    delegate :subscription, :organization, to: :event

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

        quantified_removed_on_event_day
      else
        QuantifiedEvent.create!(
          organization_id: organization.id,
          billable_metric: matching_billable_metric,
          external_subscription_id: subscription.external_id,
          external_id: event.properties[matching_billable_metric.field_name],
          properties: event.properties,
          added_at: event.timestamp,
        )
      end
    end

    def remove_metric
      metric = QuantifiedEvent.find_by(
        organization_id: organization.id,
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
          organization_id: organization.id,
          billable_metric_id: matching_billable_metric.id,
          external_subscription_id: subscription.external_id,
          external_id: event.properties[matching_billable_metric.field_name],
        )
    end
  end
end
