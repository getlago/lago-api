# frozen_string_literal: true

module UsageAttributions
  class QueryService < BaseService
    Result = BaseResult[:rows, :groups_count, :total_amount_cents, :total_events_count, :from_datetime, :to_datetime, :currency]

    Row = Data.define(:value, :amount_cents, :events_count, :cells)
    Cell = Data.define(:charge_id, :charge_filter_id, :units, :amount_cents, :events_count)

    DEFAULT_LIMIT = 50
    MAX_LIMIT = 100
    MAX_FILTER_VALUES = 20
    MAX_FLAT_FILTERS = 3
    MAX_CUSTOM_WINDOW = 31.days
    MAX_GROUPS = 100_000
    MAX_EXECUTION_TIME = 20

    SUPPORTED_AGGREGATION_TYPES = %w[count_agg sum_agg].freeze
    PRICED_CHARGE_MODELS = %w[standard].freeze

    CLICKHOUSE_FAILURES = {
      "TOO_MANY_ROWS" => "too_many_groups",
      "TIMEOUT_EXCEEDED" => "query_timeout",
      "MEMORY_LIMIT_EXCEEDED" => "memory_limit_exceeded"
    }.freeze

    def initialize(subscription:, group_by:, filters: {}, from_datetime: nil, to_datetime: nil, charges: nil,
      split_charge: nil, limit: DEFAULT_LIMIT, offset: 0)
      @subscription = subscription
      @group_by = group_by.to_s
      @filters = filters.to_h.to_h { |code, values| [code.to_s, (values.is_a?(Array) ? values : [values]).map(&:to_s)] }
      @from_datetime = from_datetime
      @to_datetime = to_datetime
      @requested_charges = charges&.to_a
      @split_charge = split_charge
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

      assign_rows(charges.any? ? fetch_rows : [])
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
      :limit, :offset

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
      errors << "must_have_filters" if split_charge.filters.none?
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
      [from_datetime || dates_service.charges_from_datetime, subscription.started_at].max
    end

    def window_to
      [to_datetime || dates_service.charges_to_datetime, subscription.terminated_at].compact.min
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
        .includes(:billable_metric, :applied_pricing_unit, filters: {values: :billable_metric_filter})
        .to_a
    end

    def charges_by_id
      @charges_by_id ||= charges.index_by(&:id)
    end

    def fetch_rows
      query = Events::Stores::Clickhouse::AttributedUsageQuery.new(
        organization_id: organization.id,
        external_subscription_id: subscription.external_id,
        from_datetime: result.from_datetime,
        to_datetime: result.to_datetime,
        group_key: group_by,
        label_filters: filters,
        charge_columns: charges.map { charge_column(it) },
        limit:,
        offset:,
        deduplicate: organization.clickhouse_deduplication_enabled?,
        max_groups: MAX_GROUPS,
        max_execution_time: MAX_EXECUTION_TIME
      )

      ::Clickhouse::BaseRecord.with_connection { it.select_all(query.query).rows }
    end

    def charge_column(charge)
      Events::Stores::Clickhouse::AttributedUsageQuery::ChargeColumn.new(
        charge_id: charge.id,
        code: charge.billable_metric.code,
        count: charge.billable_metric.count_agg?,
        priced: priced?(charge),
        split: charge == split_charge,
        buckets: pricing_buckets(charge)
      )
    end

    def pricing_buckets(charge)
      filter_buckets = charge.filters.map do |filter|
        matching_and_ignored = Events::BillingPeriodFilters::MatchingAndIgnoredService.call(
          target_filter: Events::BillingPeriodFilters::FilterTarget.from_charge(charge:, filter:)
        )

        pricing_bucket(charge, filter.id, filter.properties, matching_and_ignored.matching_filters, matching_and_ignored.ignored_filters)
      end

      filter_buckets + [pricing_bucket(charge, nil, charge.properties, {}, [])]
    end

    def pricing_bucket(charge, charge_filter_id, properties, matching_filters, ignored_filters)
      Events::Stores::Clickhouse::AttributedUsageQuery::PricingBucket.new(
        charge_filter_id:,
        matching_filters:,
        ignored_filters:,
        unit_amount_cents: unit_amount_cents(charge, properties)
      )
    end

    def unit_amount_cents(charge, properties)
      return BigDecimal(0) unless priced?(charge)

      conversion_rate = charge.applied_pricing_unit&.conversion_rate || 1
      BigDecimal(properties["amount"].presence || 0) * conversion_rate * currency.subunit_to_unit
    end

    def priced?(charge)
      PRICED_CHARGE_MODELS.include?(charge.charge_model)
    end

    def assign_rows(rows)
      result.rows = rows.map { build_row(it) }
      result.groups_count = rows.first&.last.to_i
      result.total_amount_cents = rows.first ? BigDecimal(rows.first[4].to_s) : BigDecimal(0)
      result.total_events_count = rows.first ? rows.first[5].to_i : 0
    end

    def build_row(row)
      node, (keys, units, amounts, counts), amount_cents, events_count = row

      Row.new(
        value: node.presence,
        amount_cents: BigDecimal(amount_cents.to_s),
        events_count: events_count.to_i,
        cells: keys.each_with_index.map { |key, index| build_cell(key, units[index], amounts[index], counts[index]) }
      )
    end

    def build_cell(key, units, amount_cents, events_count)
      charge_id, charge_filter_id = Events::Stores::Clickhouse::AttributedUsageQuery.parse_column_key(key)

      Cell.new(
        charge_id:,
        charge_filter_id:,
        units: BigDecimal(units.to_s),
        amount_cents: (BigDecimal(amount_cents.to_s) if priced?(charges_by_id.fetch(charge_id))),
        events_count: events_count.to_i
      )
    end
  end
end
