# frozen_string_literal: true

module UsageAttributionValues
  # Creates the attribution values carried by ingested events, or refreshes their last_seen_at.
  #
  # Each entry is reported by the events-processor for an enriched event:
  #   {"subscription_id" => ..., "attribution_labels" => {type code => value}, "timestamp" => epoch seconds}
  # The subscription, resolved by the events-processor, gives the customer. Events carry their full
  # ancestor chain, so a value's parent is the value of its parent type in the same entry. Values
  # are upserted one tree level at a time, roots first, so that a child can reference its parent row.
  #
  # Upserting is idempotent: on an existing value, last_seen_at never goes back and a discarded
  # value is restored since it is in use.
  #
  # Placement is forward-only: a value takes the parent of its most recent event (a user moving to
  # another team moves with it), an older event never moves it back, and an event without the
  # parent level keeps the current parent. Usage is unaffected: each event's own labels are stamped
  # in ClickHouse.
  class TrackService < BaseService
    UNIQUE_INDEX = :index_usage_attribution_values_on_customer_type_and_value

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
      return result if attribution_types.empty?

      value_ids = {}

      types_by_level.each do |level_types|
        rows = level_rows(level_types, value_ids)
        next if rows.empty?

        upserted = UsageAttributionValue.upsert_all( # rubocop:disable Rails/SkipsModelValidations
          rows,
          unique_by: UNIQUE_INDEX,
          on_duplicate: ON_DUPLICATE,
          returning: %w[id customer_id usage_attribution_type_id value]
        )

        upserted.each do |row|
          value_ids[row.values_at("customer_id", "usage_attribution_type_id", "value")] = row["id"]
        end
      end

      result
    end

    private

    attr_reader :organization, :entries

    def attribution_types
      @attribution_types ||= organization.usage_attribution_types.to_a
    end

    def types_by_id
      @types_by_id ||= attribution_types.index_by(&:id)
    end

    # The types grouped by tree level, roots first. For department > team > user and a flat model:
    #   [[department, model], [team], [user]]
    def types_by_level
      types_grouped_by_level = attribution_types.group_by { |attribution_type| level_of(attribution_type) }
      sorted_levels = types_grouped_by_level.keys.sort

      sorted_levels.map { |level| types_grouped_by_level[level] }
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

    def level_rows(level_types, value_ids)
      now = Time.current

      resolved_entries.each_with_object({}) do |(customer_id, labels, seen_at), rows|
        level_types.each do |attribution_type|
          value = labels[attribution_type.code]
          next if value.nil?

          key = [customer_id, attribution_type.id, value]
          parent_id = parent_value_id(customer_id, attribution_type, labels, value_ids)
          row = rows[key]

          if row.nil?
            rows[key] = {
              organization_id: organization.id,
              customer_id:,
              usage_attribution_type_id: attribution_type.id,
              value:,
              parent_id:,
              last_seen_at: seen_at,
              created_at: now,
              updated_at: now
            }
          elsif seen_at >= row[:last_seen_at]
            # Several entries of the job hold this value: the most recent one places it, as in the upsert.
            row[:last_seen_at] = seen_at
            row[:parent_id] = parent_id || row[:parent_id]
          end
        end
      end.values
    end

    def parent_value_id(customer_id, attribution_type, labels, value_ids)
      parent_type = types_by_id[attribution_type.parent_id]

      if parent_type
        value_ids[[customer_id, parent_type.id, labels[parent_type.code]]]
      end
    end

    # [customer_id, labels, seen_at] for the entries whose subscription belongs to the organization.
    def resolved_entries
      @resolved_entries ||= entries.filter_map do |entry|
        customer_id = customer_ids_by_subscription[entry["subscription_id"]]
        labels = entry["attribution_labels"]

        if customer_id && labels.is_a?(Hash)
          [customer_id, labels, Time.zone.at(entry["timestamp"].to_f)]
        end
      end
    end

    def customer_ids_by_subscription
      @customer_ids_by_subscription ||= organization.subscriptions
        .where(id: entries.pluck("subscription_id").compact.uniq)
        .pluck(:id, :customer_id)
        .to_h
    end
  end
end
