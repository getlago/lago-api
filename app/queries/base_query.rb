# frozen_string_literal: true

class BaseQuery < BaseService
  # nil values force Kaminari to apply its default values for page and limit.
  DEFAULT_PAGINATION_PARAMS = {page: nil, limit: nil}
  DEFAULT_ORDER = {created_at: :desc}
  UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  Pagination = Struct.new(:page, :limit, keyword_init: true)
  Filters = BaseFilters

  # Restores a capped `total_count` on a `without_count` relation, so that pagination
  # metadata keeps working without counting every matching row.
  module CappedTotalCount
    # Highest number of records the pagination will report. Beyond it, the total is
    # MAX_COUNTED_RECORDS and callers must treat it as "at least that many".
    MAX_COUNTED_RECORDS = 10_000

    def total_count(*)
      [counted_records, MAX_COUNTED_RECORDS].min
    end

    def total_pages
      (total_count.to_f / limit_value).ceil
    end

    def capped_total_count?
      counted_records > MAX_COUNTED_RECORDS
    end

    # Exact even beyond the cap: `without_count` fetches one extra record to know
    # whether a next page exists, so navigation is not bounded by the capped total.
    # `last_page?` is false for an out of range page, hence the two conditions.
    def has_next_page?
      !out_of_range? && !last_page?
    end

    private

    # Counts one past the cap, so that a result set landing exactly on it is reported
    # as an exact total rather than as a lower bound.
    def counted_records
      @counted_records ||= except(:offset, :limit, :order, :includes, :preload, :eager_load)
        .limit(MAX_COUNTED_RECORDS + 1)
        .count
    end
  end

  def initialize(organization:, pagination: DEFAULT_PAGINATION_PARAMS, filters: {}, search_term: nil, order: nil)
    @organization = organization
    @pagination_params = pagination
    @filters = self.class::Filters.new(**(filters || {}))
    @search_term = search_term.to_s.strip
    @order = order

    super
  end

  private

  attr_reader :organization, :pagination_params, :filters, :search_term, :order

  def validate_filters
    validation_result = filters_contract.call(filters.to_h)

    unless validation_result.success?
      errors = validation_result.errors.to_h
      result.validation_failure!(errors:)
    end

    result
  end

  def pagination
    return if pagination_params.blank?

    @pagination ||= Pagination.new(
      page: pagination_params[:page],
      limit: pagination_params[:limit]
    )
  end

  def paginate(scope)
    return scope unless pagination

    scope.page(pagination.page).per(pagination.limit)
  end

  def parse_datetime_filter(field_name)
    value = filters[field_name]
    return value if Utils::Datetime.datetime_like?(value)

    parsed_value = Utils::Datetime.parse_iso8601(value)
    return parsed_value if parsed_value

    result.single_validation_failure!(field: field_name.to_sym, error_code: "invalid_date")
      .raise_if_error!
  end

  # Apply consistent ordering across query objects
  def apply_consistent_ordering(scope, default_order: DEFAULT_ORDER)
    scope.order(default_order).order(id: :asc)
  end
end
