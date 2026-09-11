# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    # Rewrites the ignored filters into an equivalent, much smaller, list of clauses.
    #
    # An ignored filter is a conjunction of `key IN (values)` conditions, and the event stores
    # render the whole list as `NOT (clause_1 OR clause_2 OR ...)`. On charges holding thousands
    # of filters, the default filter ignores every sibling and the SQL grows past the ClickHouse
    # `max_query_size` limit, which makes the aggregation fail.
    #
    # Merging can turn two clauses into one covering a third, and dropping a clause can bring the
    # two remaining ones down to a single key, so the rewrites are applied until the list stops
    # shrinking. None of them changes the set of matched events.
    class MinimizeIgnoredFiltersService < BaseService
      Result = BaseResult[:ignored_filters]

      def initialize(ignored_filters:)
        @ignored_filters = ignored_filters
        super
      end

      def call
        filters = factorize(normalized_filters)

        loop do
          reduced = factorize(absorb(filters))
          break if reduced == filters

          filters = reduced
        end

        result.ignored_filters = filters
        result
      end

      private

      attr_reader :ignored_filters

      # Mirrors what the stores already skip when rendering the SQL: a key without values, and
      # a clause left without any key. Dropping them here changes the list, not the query.
      def normalized_filters
        ignored_filters.filter_map do |filter|
          filter.filter_map { |key, values| [key, values.uniq] if values.present? }.to_h.presence
        end
      end

      # `(a = 1 AND b = 2) OR (a = 1 AND b = 3)` is rewritten as `a = 1 AND b IN (2, 3)`.
      def factorize(filters)
        filters.group_by { |filter| filter.keys.sort }.flat_map do |keys, group|
          keys.reduce(group) { |merged, pivot| merge_on(merged, pivot) }
        end
      end

      def merge_on(filters, pivot)
        return filters if filters.size < 2

        filters.group_by { |filter| comparable(filter.except(pivot)) }.map do |_, group|
          if group.size == 1
            group.first
          else
            group.first.merge(pivot => group.flat_map { it[pivot] }.uniq)
          end
        end
      end

      # Comparing every pair is quadratic, which does not scale on the charges this service
      # exists for, so clauses are indexed by the values they allow on a pivot key.
      def absorb(filters)
        clauses = filters.each_with_index.to_a
        index = index_by_pivot_value(clauses)

        clauses.reject do |filter, position|
          candidates(index, filter).any? do |other, other_position|
            next false if other_position == position
            next false unless covers?(other, filter)

            # Equivalent clauses cover each other, only the first occurrence is kept.
            other_position < position || !covers?(filter, other)
          end
        end.map(&:first)
      end

      def index_by_pivot_value(clauses)
        clauses.group_by { |filter, _| filter.keys.sort }.to_h do |signature, group|
          pivot = pivot_key(signature, group)
          buckets = {}

          group.each do |clause|
            clause.first[pivot].each { (buckets[it] ||= []) << clause }
          end

          [signature, [pivot, buckets]]
        end
      end

      # The more distinct values a key holds, the smaller the buckets it produces.
      def pivot_key(signature, group)
        signature.max_by { |key| group.flat_map { |filter, _| filter[key] }.uniq.size }
      end

      # A covering clause has to allow every value this one allows, so one of them is enough
      # to narrow the search.
      def candidates(index, filter)
        keys = filter.keys

        index.filter_map do |signature, (pivot, buckets)|
          buckets[filter[pivot].first] if (signature - keys).empty?
        end.flatten(1)
      end

      # `covered` only matches events already matched by `covering` when `covering` constrains a
      # subset of the keys, and allows every value `covered` allows on those keys.
      def covers?(covering, covered)
        covering.all? do |key, values|
          covered.key?(key) && (covered[key] - values).empty?
        end
      end

      def comparable(filter)
        filter.transform_values(&:sort).sort.to_h
      end
    end
  end
end
