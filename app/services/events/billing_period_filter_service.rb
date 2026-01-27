# frozen_string_literal: true

module Events
  class BillingPeriodFilterService < BaseService
    Result = BaseResult[:charges]

    def initialize(subscription:, boundaries:)
      @subscription = subscription
      @boundaries = boundaries
      super
    end

    # Return the list of charges and filters that will be used in the billing or usage computation
    # The result will be a hash where the key is the charge id and the value is an array of filter ids
    # filter ids could also include "nil" as a default filter
    def call
      result.charges = deduplicate_filters(charges_and_filters)
      result
    end

    private

    attr_reader :subscription, :boundaries

    delegate :plan, :organization, to: :subscription

    def event_store
      @event_store ||= Events::Stores::StoreFactory.new_instance(
        organization: organization,
        subscription:,
        boundaries: {
          from_datetime: boundaries.charges_from_datetime,
          to_datetime: boundaries.charges_to_datetime
        }
      )
    end

    def distinct_event_codes
      event_store.distinct_codes
    end

    def charges_and_filters
      return charges_and_filters_from_event_codes unless organization.pre_filter_events?

      charges_and_filters_from_pre_enriched_events
    end

    # Return the list of all charges and filters that matches the event codes received in the period
    # It also includes the recurring charges and filters
    # The result will be a hash where the key is the charge id and the value is an array of filter ids
    # filter ids also include "nil" as a default filter
    def charges_and_filters_from_event_codes
      plan.charges.joins(:billable_metric).left_joins(:filters)
        .where(billable_metrics: {code: distinct_event_codes})
        .or(plan.charges.joins(:billable_metric).where(billable_metrics: {recurring: true}))
        .group("charges.id, charge_filters.id")
        .pluck("charges.id", "charge_filters.id")
        .then { group_by_charge_id(it) }
        .then { add_default_filter(it) }
    end

    # Return the list of charges and filters that matches the event pre enriched in clickhouse or Postgres for the period
    # It also includes the recurring charges and filters
    # The result will be a hash where the key is the charge id and the value is an array of filter ids
    # filter ids also include "nil" as a default filter when applicable
    def charges_and_filters_from_pre_enriched_events
      values = event_store.distinct_charges_and_filters

      charge_filter_ids = values.map(&:last).reject(&:blank?)
      charge_ids = values.map(&:first).uniq

      existing_charge_ids = plan.charges.where(id: charge_ids).pluck(:id)
      existing_charge_filters = plan.charges.joins(:filters)
        .where(charge_filters: {id: charge_filter_ids})
        .pluck("charge_filters.id")

      result = all_recurring_charges_and_filters

      values.each do |charge_id, filter_id|
        # Charge has been removed from the plan
        next unless existing_charge_ids.include?(charge_id)

        # Charge has no filters or only default bucket received usage in the period
        if filter_id.blank?
          result[charge_id] << nil
          next
        end

        # Keep only existing filters
        next unless existing_charge_filters.include?(filter_id)
        result[charge_id] << filter_id
      end

      result
    end

    def all_recurring_charges_and_filters
      plan.charges.joins(:billable_metric).left_joins(:filters)
        .where(billable_metrics: {recurring: true})
        .pluck("charges.id", "charge_filters.id")
        .then { group_by_charge_id(it) }
        .then { add_default_filter(it) }
    end

    # Group all charges and filters by charge_id
    def group_by_charge_id(rows)
      rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(charge_id, filter_id), hash|
        hash[charge_id] << filter_id
      end
    end

    # Include "default" bucket for recurring charges
    def add_default_filter(charges_and_filters)
      charges_and_filters.each_value { it << nil }
      charges_and_filters
    end

    # Make sure all filters are unique for each charge
    def deduplicate_filters(charges_and_filters)
      charges_and_filters.transform_values(&:uniq)
    end
  end
end
