# frozen_string_literal: true

module UsageAttributionValues
  # Creates the attribution values carried by ingested events, or refreshes their last_seen_at.
  #
  # Each entry is reported by the events-processor for an enriched event:
  #   {"subscription_id" => ..., "attribution_labels" => {type code => value}, "timestamp" => epoch seconds}
  # The subscription, resolved by the events-processor, gives the customer. Events carry their full
  # ancestor chain, so each entry's values are saved from the root down, and a value's parent is
  # the value of its parent type saved just before it.
  #
  # Upserting is idempotent: on an existing value, last_seen_at never goes back and a discarded
  # value is restored since it is in use.
  #
  # Placement is forward-only: a value takes the parent of its most recent event (a user moving to
  # another team moves with it), an older event never moves it back, and an event without the
  # parent level keeps the current parent. Usage is unaffected: each event's own labels are stamped
  # in ClickHouse.
  #
  # Placement and activity share last_seen_at: an event without the parent level makes older events
  # too old to move the value, so events are expected to carry their full ancestor chain.
  #
  # A customer holds at most UsageAttributionValue::MAX_PER_CUSTOMER_AND_TYPE values per type: past
  # it, new values are skipped, and so are the new values below them, which no tree path would reach.
  # Existing values are still refreshed. Concurrent calls each take the remaining capacity they read,
  # so the limit can be passed by a batch per consumer.
  class TrackService < BaseService
    UNIQUE_INDEX = :index_usage_attribution_values_on_customer_type_and_value
    MAX_VALUE_LENGTH = 255

    # In ON CONFLICT DO UPDATE, every expression reads the stored row as it was before the update.
    ON_DUPLICATE = Arel.sql(<<~SQL.squish)
      last_seen_at = GREATEST(usage_attribution_values.last_seen_at, EXCLUDED.last_seen_at),
      parent_id = CASE
        WHEN EXCLUDED.last_seen_at >= usage_attribution_values.last_seen_at
          THEN COALESCE(EXCLUDED.parent_id, usage_attribution_values.parent_id)
        ELSE usage_attribution_values.parent_id
      END,
      deleted_at = NULL,
      updated_at = EXCLUDED.updated_at
    SQL

    Result = BaseResult

    def initialize(organization:, entries:)
      @organization = organization
      @entries = entries

      super
    end

    def call
      return result unless organization.account_tree_enabled? && organization.clickhouse_events_store?

      # Newest first, so an older entry of the same value would change nothing and is not upserted.
      value_ids = {}

      resolved_entries.sort_by { |_, _, seen_at| -seen_at.to_f }.each do |customer_id, labels, seen_at|
        value_ids_by_type = {}
        skipped_type_ids = Set.new

        types_in_tree_order.each do |attribution_type|
          value = labels[attribution_type.code]
          next unless valid_value?(value)

          key = [customer_id, attribution_type.id, value]
          unless value_ids.key?(key)
            new_value = new_value?(customer_id, attribution_type, value)
            if new_value && (skipped_type_ids.include?(attribution_type.parent_id) || !capacity_left?(customer_id, attribution_type))
              skipped_type_ids << attribution_type.id
              next
            end

            parent_id = value_ids_by_type[attribution_type.parent_id]
            value_ids[key] = upsert_value(customer_id, attribution_type, value, parent_id, seen_at)
            remaining_capacity[[customer_id, attribution_type.id]] -= 1 if new_value
          end

          value_ids_by_type[attribution_type.id] = value_ids[key]
        end
      end

      result
    end

    private

    attr_reader :organization, :entries

    def valid_value?(value)
      value.is_a?(String) && value.present? && value.length <= MAX_VALUE_LENGTH && !value.include?("\0")
    end

    # One atomic statement per value, so consumers writing the same value at once cannot conflict.
    # Returns the id of the value, inserted or updated.
    def upsert_value(customer_id, attribution_type, value, parent_id, seen_at)
      row = {
        organization_id: organization.id,
        customer_id:,
        usage_attribution_type_id: attribution_type.id,
        value:,
        parent_id:,
        last_seen_at: seen_at,
        created_at: now,
        updated_at: now
      }

      UsageAttributionValue
        .upsert(row, unique_by: UNIQUE_INDEX, on_duplicate: ON_DUPLICATE, returning: :id) # rubocop:disable Rails/SkipsModelValidations
        .first["id"]
    end

    def new_value?(customer_id, attribution_type, value)
      !existing_values.include?([customer_id, attribution_type.id, value])
    end

    def existing_values
      @existing_values ||= UsageAttributionValue
        .where(
          customer_id: resolved_entries.map(&:first).uniq,
          usage_attribution_type_id: attribution_types.map(&:id),
          value: resolved_entries.flat_map { |_, labels, _| labels.values.select { valid_value?(it) } }.uniq
        )
        .pluck(:customer_id, :usage_attribution_type_id, :value)
        .to_set
    end

    def capacity_left?(customer_id, attribution_type)
      key = [customer_id, attribution_type.id]
      remaining_capacity[key] ||= UsageAttributionValue.remaining_capacity(customer_id:, usage_attribution_type_id: attribution_type.id)
      remaining_capacity[key].positive?
    end

    def remaining_capacity
      @remaining_capacity ||= {}
    end

    def attribution_types
      @attribution_types ||= organization.usage_attribution_types.to_a
    end

    def types_by_id
      @types_by_id ||= attribution_types.index_by(&:id)
    end

    def types_in_tree_order
      @types_in_tree_order ||= attribution_types.sort_by { |attribution_type| level_of(attribution_type) }
    end

    def level_of(attribution_type)
      level = 0
      parent_type = types_by_id[attribution_type.parent_id]

      while parent_type && level < attribution_types.size
        level += 1
        parent_type = types_by_id[parent_type.parent_id]
      end

      level
    end

    def resolved_entries
      @resolved_entries ||= entries.filter_map do |entry|
        customer_id = customer_ids_by_subscription[entry["subscription_id"]]
        labels = entry["attribution_labels"]

        timestamp = entry["timestamp"]

        if customer_id && labels.is_a?(Hash) && timestamp.is_a?(Numeric)
          [customer_id, labels, [Time.zone.at(timestamp), now].min]
        end
      end
    end

    def now
      @now ||= Time.current
    end

    def customer_ids_by_subscription
      @customer_ids_by_subscription ||= organization.subscriptions
        .joins(:customer).merge(Customer.kept)
        .where(id: entries.pluck("subscription_id").compact.uniq)
        .pluck(:id, :customer_id)
        .to_h
    end
  end
end
