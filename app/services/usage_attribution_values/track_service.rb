# frozen_string_literal: true

module UsageAttributionValues
  # Creates the attribution values carried by ingested events, or refreshes their last_seen_at.
  #
  # Each entry holds the labels of an event ({type code => value}) and the subscription it was
  # ingested for, which gives the customer. Events carry their full ancestor chain, so a value's
  # parent is the value of its parent type in the same entry. Values are upserted one tree level at
  # a time, roots first, so that a child can reference its parent row.
  #
  # Upserting is idempotent: on an existing value, last_seen_at never goes back, the first parent
  # is kept (re-parenting is out of scope), and a discarded value is restored since it is in use.
  class TrackService < BaseService
    UNIQUE_INDEX = :index_usage_attribution_values_on_customer_type_and_value

    ON_DUPLICATE = Arel.sql(<<~SQL.squish)
      last_seen_at = GREATEST(usage_attribution_values.last_seen_at, EXCLUDED.last_seen_at),
      parent_id = COALESCE(usage_attribution_values.parent_id, EXCLUDED.parent_id),
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

    def types_by_level
      levels = Hash.new { |cache, type| cache[type] = types_by_id[type.parent_id] ? cache[types_by_id[type.parent_id]] + 1 : 0 }

      attribution_types.group_by { levels[it] }.sort.map(&:last)
    end

    def level_rows(level_types, value_ids)
      now = Time.current

      resolved_entries.each_with_object({}) do |(customer_id, labels, seen_at), rows|
        level_types.each do |attribution_type|
          value = labels[attribution_type.code]
          next if value.nil?

          key = [customer_id, attribution_type.id, value]
          row = rows[key] ||= {
            organization_id: organization.id,
            customer_id:,
            usage_attribution_type_id: attribution_type.id,
            value:,
            parent_id: parent_value_id(customer_id, attribution_type, labels, value_ids),
            last_seen_at: seen_at,
            created_at: now,
            updated_at: now
          }
          row[:last_seen_at] = [row[:last_seen_at], seen_at].max
        end
      end.values
    end

    def parent_value_id(customer_id, attribution_type, labels, value_ids)
      parent_type = types_by_id[attribution_type.parent_id]

      if parent_type
        value_ids[[customer_id, parent_type.id, labels[parent_type.code]]]
      end
    end

    def resolved_entries
      @resolved_entries ||= entries.filter_map do |entry|
        seen_at = Time.zone.parse(entry["seen_at"])
        customer_id = subscription_customer_id(entry["external_subscription_id"], seen_at)

        if customer_id
          [customer_id, entry["labels"], seen_at]
        end
      end
    end

    def subscription_customer_id(external_subscription_id, timestamp)
      organization.subscriptions
        .where(external_id: external_subscription_id)
        .where("date_trunc('millisecond', started_at::timestamp) <= ?::timestamp", timestamp)
        .where("terminated_at IS NULL OR date_trunc('millisecond', terminated_at::timestamp) >= ?", timestamp)
        .order("terminated_at DESC NULLS FIRST, started_at DESC")
        .pick(:customer_id)
    end
  end
end
