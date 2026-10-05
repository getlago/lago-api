# frozen_string_literal: true

module UsageAttributions
  # Resolves which filter of a charge prices an event, as a lookup ClickHouse can apply per event.
  #
  # An event belongs to the matching filter with the most keys, the oldest one on a tie (same rule
  # as `ChargeFilters::EventMatchingService` and the events-processor). Filters are ranked in that
  # order, then grouped by their set of keys: each group maps the joined filter values to the rank
  # of the best filter holding them, so an event resolves with one hash lookup per group and keeps
  # the lowest rank found. Ranks index `filter_ids` and `unit_amounts_cents`.
  #
  # The lookup is cached until the charge, its filters, their values or the pricing unit change.
  # It is nil when expanding the filter values exceeds MAX_ENTRIES.
  class ChargePriceLookupService < BaseService
    SEPARATOR = "\u001F"
    MAX_ENTRIES = 20_000
    CACHE_TTL = 1.hour

    Lookup = Data.define(:key_sets, :filter_ids, :unit_amounts_cents)
    Result = BaseResult[:lookup]

    def initialize(charge:, currency:)
      @charge = charge
      @currency = currency

      super
    end

    def call
      result.lookup = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { build_lookup }
      result
    end

    private

    attr_reader :charge, :currency

    def build_lookup
      ranked = ranked_filters
      return if ranked.sum { |filter| filter[:values].values.map(&:size).reduce(1, :*) } > MAX_ENTRIES

      key_sets = {}
      ranked.each.with_index(1) do |filter, rank|
        keys = filter[:values].keys.sort
        entries = (key_sets[keys] ||= {})
        first, *rest = keys.map { filter[:values][it] }
        first.product(*rest).each { entries[it.join(SEPARATOR)] ||= rank }
      end

      Lookup.new(
        key_sets: key_sets.each_with_index.sort_by { |(keys, _), index| [-keys.size, index] }.map(&:first),
        filter_ids: ranked.map { it[:id] },
        unit_amounts_cents: ranked.map { unit_amount_cents(it[:amount]) }
      )
    end

    def ranked_filters
      filters = {}
      filter_rows.each do |id, amount, key, values, all_values|
        filter = (filters[id] ||= {id:, amount:, values: {}})
        filter[:values][key] = (values == [ChargeFilterValue::ALL_FILTER_VALUES]) ? all_values : values
      end

      filters.values
        .reject { it[:values].empty? }
        .each_with_index
        .sort_by { |filter, position| [-filter[:values].size, position] }
        .map(&:first)
    end

    def filter_rows
      ChargeFilterValue
        .joins(:charge_filter, :billable_metric_filter)
        .where(charge_filters: {charge_id: charge.id, deleted_at: nil})
        .reorder("charge_filters.updated_at ASC, charge_filters.id ASC")
        .pluck(
          "charge_filters.id",
          Arel.sql("charge_filters.properties ->> 'amount'"),
          "billable_metric_filters.key",
          "charge_filter_values.values",
          "billable_metric_filters.values"
        )
    end

    def unit_amount_cents(amount)
      BigDecimal(amount.presence || 0) * conversion_rate * currency.subunit_to_unit
    end

    def conversion_rate
      charge.applied_pricing_unit&.conversion_rate || 1
    end

    def cache_key
      values_updated_at, values_count = ChargeFilterValue.unscoped
        .joins(:charge_filter)
        .where(charge_filters: {charge_id: charge.id})
        .pick(Arel.sql("MAX(charge_filter_values.updated_at)"), Arel.sql("COUNT(*)"))
      metric_filters_updated_at = BillableMetricFilter.unscoped
        .where(billable_metric_id: charge.billable_metric_id)
        .maximum(:updated_at)

      [
        "usage_attributions/charge_price_lookup/v1",
        charge.id,
        stamp(charge.updated_at),
        stamp(values_updated_at),
        values_count,
        stamp(metric_filters_updated_at),
        stamp(charge.applied_pricing_unit&.updated_at),
        currency.iso_code
      ].join("/")
    end

    def stamp(time)
      time&.utc&.iso8601(6)
    end
  end
end
