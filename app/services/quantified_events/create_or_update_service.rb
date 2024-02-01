# frozen_string_literal: true

module QuantifiedEvents
  class CreateOrUpdateService < BaseService
    def initialize(event)
      @event = event

      super(nil)
    end

    def call
      result.quantified_events = case event_operation_type
                                 when :add
                                   add_metric
                                 when :remove
                                   remove_metric
      end

      result
    end

    def matching_billable_metric?
      matching_billable_metric&.unique_count_agg?
    end

    def process_event?
      return true unless event_operation_type == :add
      return true unless matching_billable_metric&.unique_count_agg?

      # NOTE: Ensure no active quantified metric exists with the same external id and groups
      matching_charge_grouped_properties.any? do |grouped_by|
        QuantifiedEvent.where(
          organization_id: organization.id,
          billable_metric_id: matching_billable_metric.id,
          external_id: event.properties[matching_billable_metric.field_name],
          external_subscription_id: event.external_subscription_id,
          grouped_by:,
        ).where(removed_at: nil).none?
      end
    end

    private

    attr_accessor :event

    delegate :organization, to: :event

    def event_operation_type
      operation_type = event.properties['operation_type']&.to_sym
      (operation_type.nil? && matching_billable_metric&.unique_count_agg?) ? :add : operation_type
    end

    def add_metric
      matching_charge_grouped_properties.map do |grouped_by|
        # NOTE: if we add a quantified event removed on the same day,
        #       since the granularity is on day
        #       we just need to set the removed_at field back to nil to
        #       prevent wrong units count
        quantified_event = find_quantified_removed_on_event_day(grouped_by:)

        if quantified_event.present?
          quantified_event.update!(removed_at: nil)

          quantified_event
        else
          QuantifiedEvent.create!(
            organization_id: organization.id,
            billable_metric: matching_billable_metric,
            external_subscription_id: event.external_subscription_id,
            external_id: event.properties[matching_billable_metric.field_name],
            properties: event.properties,
            added_at: event.timestamp,
            grouped_by:,
          )
        end
      end
    end

    def remove_metric
      matching_charge_grouped_properties.map do |grouped_by|
        metric = QuantifiedEvent.find_by(
          organization_id: organization.id,
          billable_metric_id: matching_billable_metric.id,
          external_subscription_id: event.external_subscription_id,
          external_id: event.properties[matching_billable_metric.field_name],
          removed_at: nil,
          grouped_by:,
        )

        next if metric.blank?

        metric.update!(removed_at: event.timestamp)
        metric
      end.compact
    end

    def matching_billable_metric
      @matching_billable_metric ||= organization.billable_metrics.find_by(
        code: event.code,
      )
    end

    def find_quantified_removed_on_event_day(grouped_by:)
      QuantifiedEvent
        .where('DATE(removed_at) = ?', event.timestamp.to_date)
        .find_by(
          organization_id: organization.id,
          billable_metric_id: matching_billable_metric.id,
          external_subscription_id: event.external_subscription_id,
          external_id: event.properties[matching_billable_metric.field_name],
          grouped_by:,
        )
    end

    def matching_charges
      @matching_charges ||= matching_billable_metric.charges.where(plan_id: event.subscription&.plan_id)
    end

    def matching_charge_grouped_properties
      return [{}] if matching_charges.none?

      matching_charges.map do |charge|
        next {} unless charge.standard?
        next {} if charge.properties['grouped_by'].blank?

        charge.properties['grouped_by'].index_with do |group|
          event.properties[group]
        end
      end.uniq
    end
  end
end
