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
      existing_charge_filters = fetch_existing_filters(charge_filter_ids)

      result = recurring_charges_and_filters

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

    def recurring_charges_and_filters
      # First period: no previous usage exists, events from current period are enough
      return Hash.new { |h, k| h[k] = [] } if subscription.started_at >= boundaries.charges_from_datetime

      # If the subscription was upgraded, use the upgrade chain to filter recurring charges
      return recurring_charges_and_filters_from_upgrade_chain if subscription.previous_subscription_id.present?

      # Use previous fees to filter the recurring charges with existing usage
      recurring_charges_and_filters_from_previous_fees
    end

    def recurring_charges_and_filters_from_previous_fees
      pairs = current_subscription_recurring_fees

      return Hash.new { |h, k| h[k] = [] } if pairs.empty?

      filter_ids = pairs.map(&:last).compact
      if filter_ids.any?
        existing_filter_ids = fetch_existing_filters(filter_ids)
        pairs = pairs.select { |_, f_id| f_id.nil? || existing_filter_ids.include?(f_id) }
      end

      pairs.then { group_by_charge_id(it) }
    end

    def recurring_charges_and_filters_from_upgrade_chain
      # First, let's fetch fees from the current subscription created before the current period
      result = current_subscription_recurring_fees
        .then { group_by_charge_id(it) }

      # Then, include all filters for charges whose billable metric had previous usage
      previous_bm_ids = previous_subscriptions_billable_metric_ids
      return result if previous_bm_ids.empty?

      current_recurring_charges.each do |charge|
        next unless previous_bm_ids.include?(charge.billable_metric_id)

        filter_ids = charge.filters.map(&:id)
        result[charge.id] = (result[charge.id] + filter_ids + [nil]).uniq
      end
      result
    end

    def current_recurring_charges
      @current_recurring_charges ||= plan.charges
        .joins(:billable_metric)
        .where(billable_metrics: {recurring: true})
        .includes(:filters)
        .to_a
    end

    def previous_subscriptions_billable_metric_ids
      previous_sub_ids = collect_previous_subscription_ids
      return Set.new if previous_sub_ids.empty?

      bm_ids = current_recurring_charges.map(&:billable_metric_id)
      return Set.new if bm_ids.empty?

      Fee.where(subscription_id: previous_sub_ids, fee_type: :charge)
        .joins(charge: :billable_metric)
        .where(billable_metrics: {id: bm_ids})
        .distinct
        .pluck(:billable_metric_id)
        .to_set
    end

    def collect_previous_subscription_ids
      organization.subscriptions
        .terminated
        .where(external_id: subscription.external_id, customer_id: subscription.customer_id)
        .where.not(id: subscription.id)
        .pluck(:id)
    end

    def current_subscription_recurring_fees
      Fee.where(subscription_id: subscription.id, fee_type: :charge)
        .joins(invoice: :invoice_subscriptions)
        .where("invoice_subscriptions.subscription_id = fees.subscription_id")
        .where("invoice_subscriptions.charges_from_datetime < ?", boundaries.charges_from_datetime)
        .joins(charge: :billable_metric)
        .where(charges: {plan_id: plan.id, deleted_at: nil})
        .where(billable_metrics: {recurring: true})
        .distinct
        .pluck(:charge_id, :charge_filter_id)
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

    def fetch_existing_filters(charge_filter_ids)
      plan.charges.joins(:filters)
        .where(charge_filters: {id: charge_filter_ids})
        .pluck("charge_filters.id")
    end
  end
end
