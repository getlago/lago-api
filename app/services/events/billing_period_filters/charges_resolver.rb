# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    class ChargesResolver < BaseResolver
      def initialize(subscription:, boundaries:, codes: nil, with_last_seen_at: true)
        @subscription = subscription
        @boundaries = boundaries
        @codes = codes
        @with_last_seen_at = with_last_seen_at
      end

      def filter_targets
        if organization.pre_filter_events?
          filter_targets_from_pre_enriched_events
        else
          filter_targets_from_events
        end
      end

      private

      attr_reader :subscription, :boundaries, :codes, :with_last_seen_at

      delegate :organization, :plan, to: :subscription

      def period_start
        boundaries.charges_from_datetime
      end

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

      # A code outside of the plan matches no event, so codes is used as is: dropping it would leave
      # its charge out of the result, billed as zero units instead of surfaced.
      def plan_codes
        @plan_codes ||= codes || plan.billable_metrics.distinct.pluck(:code)
      end

      def filter_targets_from_events
        combinations = event_store.distinct_codes_and_property_combinations(
          codes: non_recurring_plan_codes,
          filter_keys: billable_metric_filter_keys,
          with_last_seen_at:
        )

        # Recurring usage carries over all-time, so its lazy cache key must reflect events ingested
        # for prior periods.
        if recurring_plan_codes.any?
          combinations += event_store.distinct_codes_and_property_combinations(
            codes: recurring_plan_codes,
            filter_keys: billable_metric_filter_keys,
            include_all_history: true,
            with_last_seen_at:
          )
        end

        filter_targets_from_combinations(
          combinations:,
          targets: charges_with_events(combinations.map(&:first).uniq),
          result: recurring_event_filter_targets
        )
      end

      def filter_target_for(charge)
        Events::BillingPeriodFilters::FilterTarget.from_charge(charge:)
      end

      def recurring_event_filter_targets
        result = {}

        current_recurring_charges.each do |charge|
          if charge.filters.any?
            charge.filters.each { |filter| record(result, charge.target_key, filter.id, period_start) }
          else
            record(result, charge.target_key, nil, period_start)
          end
        end

        result.each_key { |target_key| record(result, target_key, nil, period_start) }
        result
      end

      def charges_with_events(codes)
        plan.charges
          .joins(:billable_metric)
          .where(billable_metrics: {code: codes})
          .includes(billable_metric: :filters, filters: {values: :billable_metric_filter})
      end

      def billable_metric_filter_keys
        @billable_metric_filter_keys ||= BillableMetricFilter
          .where(billable_metric_id: plan.billable_metrics.where(code: plan_codes).select(:id))
          .distinct
          .pluck(:key)
      end

      def filter_targets_from_pre_enriched_events
        values = event_store.distinct_charges_and_filters(codes: non_recurring_plan_codes, with_last_seen_at:)

        # Recurring usage carries over all-time, so its lazy cache key must reflect events ingested
        # for prior periods.
        if recurring_plan_codes.any?
          values += event_store.distinct_charges_and_filters(
            codes: recurring_plan_codes,
            include_all_history: true,
            with_last_seen_at:
          )
        end

        charge_filter_ids = values.map { |v| v[1] }.reject(&:blank?)
        charge_ids = values.map(&:first).uniq

        existing_charges = plan.charges.where(id: charge_ids).index_by(&:id)
        existing_charge_filters = fetch_existing_filters(charge_filter_ids)

        result = recurring_filter_targets

        values.each do |charge_id, filter_id, last_seen_at|
          charge = existing_charges[charge_id]
          next unless charge

          if filter_id.blank?
            record(result, charge.target_key, nil, last_seen_at)
            next
          end

          next unless existing_charge_filters.include?(filter_id)

          record(result, charge.target_key, filter_id, last_seen_at)
        end

        result
      end

      def recurring_filter_targets
        return {} if subscription.started_at >= boundaries.charges_from_datetime
        return recurring_filter_targets_from_upgrade_chain if subscription.previous_subscription_id.present?

        recurring_filter_targets_from_previous_fees
      end

      def recurring_filter_targets_from_previous_fees
        pairs = current_subscription_recurring_fees

        return {} if pairs.empty?

        filter_ids = pairs.map(&:last).compact
        if filter_ids.any?
          existing_filter_ids = fetch_existing_filters(filter_ids)
          pairs = pairs.select { |_, f_id| f_id.nil? || existing_filter_ids.include?(f_id) }
        end

        group_by_charge_id(pairs)
      end

      def recurring_filter_targets_from_upgrade_chain
        result = group_by_charge_id(current_subscription_recurring_fees)

        previous_bm_ids = previous_subscriptions_billable_metric_ids
        return result if previous_bm_ids.empty?

        current_recurring_charges.each do |charge|
          next unless previous_bm_ids.include?(charge.billable_metric_id)

          charge.filters.each { |filter| record(result, charge.target_key, filter.id, period_start) }
          record(result, charge.target_key, nil, period_start)
        end
        result
      end

      def recurring_plan_codes
        @recurring_plan_codes ||= plan.billable_metrics.where(recurring: true).where(code: plan_codes).distinct.pluck(:code)
      end

      def non_recurring_plan_codes
        @non_recurring_plan_codes ||= plan_codes - recurring_plan_codes
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
          .positive_units
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
          .positive_units
          .distinct
          .pluck(:charge_id, :charge_filter_id)
      end

      def group_by_charge_id(rows)
        charges = current_charges_by_id(rows.map(&:first))

        rows.each_with_object({}) do |(charge_id, filter_id), accumulator|
          charge = charges[charge_id]
          if charge
            record(accumulator, charge.target_key, filter_id, period_start)
          end
        end
      end

      def current_charges_by_id(charge_ids)
        plan.charges.where(id: charge_ids).index_by(&:id)
      end

      def fetch_existing_filters(charge_filter_ids)
        plan.charges.joins(:filters)
          .where(charge_filters: {id: charge_filter_ids})
          .pluck("charge_filters.id")
      end
    end
  end
end
