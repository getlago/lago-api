# frozen_string_literal: true

module RealtimeUsage
  module Reports
    # A dimension is what a usage is split on: the values of its charge filter and of its
    # pricing group keys. Charge filters belong to one charge, so two plans filtering a metric on
    # the same region have two filter ids; the key is built from the values instead, which lets
    # the report merge them. The stream writes grouped_by as JSONB text, whose keys are already
    # in a canonical order.
    class DimensionKey
      # A control character JSON always escapes, so neither part can contain it.
      SEPARATOR = "\u001f"

      Dimension = Struct.new(:key, :name, :values)

      # Buckets outlive the filters they were counted on, so a deleted filter still names its
      # usage, with the values it had when it was deleted.
      def self.build(organization:, charge_filter_ids:)
        discarded_ids = ChargeFilter.with_discarded.discarded
          .where(organization_id: organization.id, id: charge_filter_ids)
          .pluck(:id).to_set

        filters = ChargeFilterValue.with_discarded
          .where(organization_id: organization.id, charge_filter_id: charge_filter_ids)
          .includes(:billable_metric_filter)
          .select { |value| value.deleted_at.nil? || discarded_ids.include?(value.charge_filter_id) }
          .group_by(&:charge_filter_id)
          .transform_values { |values| values.to_h { |value| [value.billable_metric_filter.key, value.values] } }

        new(filters:)
      end

      # filters maps a charge filter id to its values, as ChargeFilter#to_h returns them.
      def initialize(filters:)
        @filter_parts = filters.transform_values { |values| JSON.generate(values.sort.to_h { |key, key_values| [key, key_values.sort] }) }
      end

      # Every bucket gets its key in ClickHouse, so a report groups on it directly whatever the
      # number of filters and plans behind it.
      def sql
        filter_part = if filter_parts.empty?
          "''"
        else
          "transform(charge_filter_id, [#{quote_list(filter_parts.keys)}], [#{quote_list(filter_parts.values)}], '')"
        end

        "concat(#{filter_part}, char(31), if(grouped_by IN ('', '{}'), '', grouped_by))"
      end

      def dimension(key)
        filter_part, grouped_by_part = key.split(SEPARATOR, 2)
        values = parse(filter_part).merge(parse(grouped_by_part).transform_values { |value| Array(value).map(&:to_s) })

        Dimension.new(key, name(values), values)
      end

      private

      attr_reader :filter_parts

      def parse(part)
        part.present? ? JSON.parse(part) : {}
      end

      # The same name an invoice gives a filter without a display name: a filter on every value
      # of a key reads as the key itself. The usage of a charge's default bucket has no name.
      def name(values)
        names = values.flat_map do |key, key_values|
          (key_values == [ChargeFilterValue::ALL_FILTER_VALUES]) ? key : key_values
        end

        names.join(", ").presence
      end

      def quote_list(values)
        values.map { |value| Clickhouse::UsageBucket.connection.quote(value) }.join(", ")
      end
    end
  end
end
