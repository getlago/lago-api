# frozen_string_literal: true

module UsageAttributions
  class QueryService < BaseService
    Result = BaseResult[:rows, :unattributed, :others, :others_count, :totals, :groups_count, :from_datetime, :to_datetime, :currency]

    Row = Data.define(:value, :rank, :amount_cents, :events_count, :cells)
    Aggregate = Data.define(:amount_cents, :events_count, :cells)
    Cell = Data.define(:charge_id, :charge_filter_id, :units, :amount_cents, :events_count)

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100
    MAX_FILTER_VALUES = 20
    MAX_FLAT_FILTERS = 3
    MAX_SPLIT_FILTERS = 10
    MAX_SEARCH_LENGTH = 100
    MAX_CUSTOM_WINDOW = 31.days
    MAX_GROUPS = 250_000
    MAX_EXECUTION_TIME = 8
    MAX_MEMORY_USAGE = 4_000_000_000

    ORDERS = %w[amount events_count].freeze
    SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze
    PRICED_CHARGE_MODELS = %w[standard].freeze

    CLICKHOUSE_FAILURES = {
      "TOO_MANY_ROWS" => "too_many_groups",
      "TIMEOUT_EXCEEDED" => "query_timeout",
      "MEMORY_LIMIT_EXCEEDED" => "memory_limit_exceeded"
    }.freeze

    def initialize(subscription:, group_by:, filters: {}, from_datetime: nil, to_datetime: nil, charges: nil,
      split_charge: nil, search: nil, order_by: "amount", limit: DEFAULT_LIMIT, offset: 0)
      @subscription = subscription
      @group_by = group_by.to_s
      @filters = filters.to_h.to_h { |code, values| [code.to_s, (values.is_a?(Array) ? values : [values]).map(&:to_s)] }
      @from_datetime = from_datetime
      @to_datetime = to_datetime
      @requested_charges = charges&.to_a
      @split_charge = split_charge
      @search = search.presence
      @order_by = order_by.to_s
      @limit = limit
      @offset = offset

      super
    end

    def call
      return result.not_found_failure!(resource: "subscription") unless subscription
      return result.forbidden_failure! unless available?
      return result.not_allowed_failure!(code: "subscription_not_started") unless subscription.started_at
      return result.not_found_failure!(resource: "usage_attribution_type") unless attribution_types_found?
      return result.not_found_failure!(resource: "charge") unless requested_charges_in_plan?
      return result.validation_failure!(errors: validation_errors) if validation_errors.any?

      result.from_datetime = window_from
      result.to_datetime = window_to
      result.currency = currency.iso_code

      assign_result(fetch_rows)
      result
    rescue ActiveRecord::ActiveRecordError => e
      failure_code = CLICKHOUSE_FAILURES.find { |clickhouse_code, _| e.message.include?(clickhouse_code) }&.last

      if failure_code
        result.service_failure!(code: failure_code, message: e.message)
      else
        raise
      end
    end

    private

    attr_reader :subscription, :group_by, :filters, :from_datetime, :to_datetime, :requested_charges, :split_charge,
      :search, :order_by, :limit, :offset

    delegate :organization, to: :subscription

    def available?
      Events::Stores::StoreFactory.supports_clickhouse? &&
        organization.clickhouse_events_store? &&
        organization.account_tree_enabled?
    end

    def attribution_types
      @attribution_types ||= organization.usage_attribution_types.where(code: [group_by, *filters.keys]).index_by(&:code)
    end

    def attribution_types_found?
      attribution_types.key?(group_by) && filters.keys.all? { attribution_types.key?(it) }
    end

    def validation_errors
      @validation_errors ||= {
        filters: filters_errors,
        to_datetime: window_errors,
        limit: (["value_is_out_of_range"] unless limit.is_a?(Integer) && limit.between?(1, MAX_LIMIT)),
        offset: (["value_is_out_of_range"] unless offset.is_a?(Integer) && offset >= 0),
        search: (["value_is_too_long"] if search && search.length > MAX_SEARCH_LENGTH),
        order_by: (["value_is_invalid"] unless ORDERS.include?(order_by)),
        charges: charges_errors,
        split_charge: split_charge_errors
      }.compact_blank
    end

    def charges_errors
      return [] if requested_charges.nil?
      return ["must_not_be_empty"] if requested_charges.empty?

      (requested_charges.all? { supported_charge?(it) }) ? [] : ["unsupported_aggregation_type"]
    end

    def split_charge_errors
      return [] if split_charge.nil?

      errors = []
      errors << "unsupported_aggregation_type" unless supported_charge?(split_charge)
      errors << "must_be_selected" if requested_charges&.exclude?(split_charge)

      filters_count = filters_count_by_charge_id.fetch(split_charge.id, 0)
      if filters_count.zero?
        errors << "must_have_filters"
      elsif filters_count > MAX_SPLIT_FILTERS || (supported_charge?(split_charge) && price_lookup(split_charge).nil?)
        errors << "too_many_filters"
      end

      errors
    end

    def requested_charges_in_plan?
      [*requested_charges, split_charge].compact.all? { it.plan_id == subscription.plan_id }
    end

    def filters_errors
      errors = []
      errors << "values_are_required" if filters.values.any?(&:empty?)
      errors << "too_many_values" if filters.values.any? { it.size > MAX_FILTER_VALUES }
      errors << "too_many_flat_filters" if filters.keys.count { attribution_types[it].flat? } > MAX_FLAT_FILTERS
      errors
    end

    def window_errors
      return [] if from_datetime.nil? && to_datetime.nil?
      return ["both_boundaries_are_required"] if from_datetime.nil? || to_datetime.nil?
      return ["invalid_date_range"] if from_datetime >= to_datetime
      return ["window_too_long"] if to_datetime - from_datetime > MAX_CUSTOM_WINDOW

      []
    end

    def window_from
      [from_datetime || default_window.first, subscription.started_at].max
    end

    def window_to
      [to_datetime || default_window.last, subscription.terminated_at].compact.min
    end

    # The current billing period. A period longer than a custom window (quarterly or yearly charges)
    # is narrowed to its last MAX_CUSTOM_WINDOW up to now, so the default view scans as much as a
    # custom one at most.
    def default_window
      @default_window ||= begin
        period_from = dates_service.charges_from_datetime
        period_to = dates_service.charges_to_datetime

        if period_to - period_from > MAX_CUSTOM_WINDOW
          period_to = [period_to, Time.current].min
          period_from = [period_from, period_to - MAX_CUSTOM_WINDOW].max
        end

        [period_from, period_to]
      end
    end

    def dates_service
      @dates_service ||= Subscriptions::DatesService.new_instance(subscription, Time.current, current_usage: true)
    end

    def currency
      @currency ||= Money::Currency.new(subscription.plan.amount_currency)
    end

    def charges
      @charges ||= if requested_charges
        supported_charges.select { requested_charges.include?(it) }
      else
        supported_charges
      end
    end

    def supported_charge?(charge)
      supported_charges.include?(charge)
    end

    def supported_charges
      @supported_charges ||= subscription.plan.charges
        .joins(:billable_metric)
        .where(billable_metrics: {aggregation_type: SUPPORTED_AGGREGATION_TYPES, recurring: false})
        .includes(:billable_metric, :applied_pricing_unit)
        .to_a
    end

    def filters_count_by_charge_id
      @filters_count_by_charge_id ||= ChargeFilter.unscope(:order)
        .where(charge_id: [*supported_charges, split_charge].compact.map(&:id))
        .group(:charge_id)
        .count
    end

    def price_lookup(charge)
      @price_lookups ||= {}
      return @price_lookups[charge.id] if @price_lookups.key?(charge.id)

      @price_lookups[charge.id] = ChargePriceLookupService.call!(charge:, currency:).lookup
    end

    # A plan may hold no count or sum charge: there is nothing to read then.
    def fetch_rows
      return [] if charges.empty?

      query = Events::Stores::Clickhouse::AttributedUsageQuery.new(
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        from_datetime: result.from_datetime,
        to_datetime: result.to_datetime,
        group_key: group_by,
        label_filters: filters,
        charge_columns: charges.map { charge_column(it) },
        order_by:,
        search:,
        limit:,
        offset:,
        deduplicate: organization.clickhouse_deduplication_enabled?,
        max_groups: MAX_GROUPS,
        max_execution_time: MAX_EXECUTION_TIME,
        max_memory_usage: MAX_MEMORY_USAGE
      )
      @cells = query.cells
      query.rows
    end

    def charge_column(charge)
      split = charge == split_charge
      filtered = filters_count_by_charge_id.key?(charge.id)
      lookup = price_lookup(charge) if filtered && (priced?(charge) || split)
      priced = priced?(charge) && (!filtered || lookup.present?)

      Events::Stores::Clickhouse::AttributedUsageQuery::ChargeColumn.new(
        charge_id: charge.id,
        code: charge.billable_metric.code,
        count: charge.billable_metric.count_agg?,
        unit_amount_cents: (unit_amount_cents(charge) if priced),
        lookup:,
        split:
      )
    end

    def unit_amount_cents(charge)
      conversion_rate = charge.applied_pricing_unit&.conversion_rate || 1
      BigDecimal(charge.properties["amount"].presence || 0) * conversion_rate * currency.subunit_to_unit
    end

    def priced?(charge)
      PRICED_CHARGE_MODELS.include?(charge.charge_model)
    end

    def assign_result(rows)
      ranked = rows.reject { it["node"] == "" }
      unattributed = rows.find { it["node"] == "" }
      page = ranked.select { it["in_page"].to_i == 1 }
      level = ranked.first

      result.rows = page.map { build_row(it) }
      result.unattributed = (build_aggregate { value(unattributed, it) } if unattributed)
      result.groups_count = level ? level["groups_count"].to_i : 0
      result.totals = build_aggregate { value(level, "total_#{it}") + value(unattributed, it) }
      result.others_count = others_count(page)
      result.others = build_others(level, page)
    end

    def others_count(page)
      if search
        result.groups_count - page.size
      elsif page.any?
        result.groups_count - page.last["rank"].to_i
      else
        0
      end
    end

    # Everything ranked after the page. A page is contiguous, so the running total at its last row
    # covers it and every page before; search results are not, so they are subtracted one by one.
    def build_others(level, page)
      if result.others_count.zero?
        build_aggregate { 0 }
      elsif search
        build_aggregate { |name| value(level, "total_#{name}") - page.sum { value(it, name) } }
      else
        build_aggregate { |name| value(level, "total_#{name}") - value(page.last, "running_#{name}") }
      end
    end

    def build_row(row)
      Row.new(
        value: row["node"],
        rank: row["rank"].to_i,
        amount_cents: value(row, "amount"),
        events_count: value(row, "events").to_i,
        cells: build_cells { value(row, it) }
      )
    end

    def build_aggregate(&)
      Aggregate.new(
        amount_cents: decimal(yield("amount")),
        events_count: decimal(yield("events")).to_i,
        cells: build_cells(&)
      )
    end

    def build_cells
      Array(@cells).each_with_index.map do |cell, index|
        Cell.new(
          charge_id: cell.charge_id,
          charge_filter_id: cell.charge_filter_id,
          units: decimal(yield("units_#{index}")),
          amount_cents: (decimal(yield("amount_#{index}")) if cell.priced),
          events_count: decimal(yield("events_#{index}")).to_i
        )
      end
    end

    def value(row, name)
      decimal(row&.dig(name))
    end

    def decimal(value)
      BigDecimal((value || 0).to_s)
    end
  end
end
