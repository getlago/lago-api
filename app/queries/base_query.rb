# frozen_string_literal: true

class BaseQuery < BaseService
  # nil values force Kaminari to apply its default values for page and limit.
  DEFAULT_PAGINATION_PARAMS = {page: nil, limit: nil}
  DEFAULT_ORDER = {created_at: :desc}

  Pagination = Struct.new(:page, :limit, :cursor, keyword_init: true)
  Filters = BaseFilters

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
      limit: pagination_params[:limit],
      cursor: pagination_params[:cursor]
    )
  end

  def paginate(scope)
    return scope unless pagination

    scope.page(pagination.page).per(pagination.limit)
  end

  def parse_datetime_filter(field_name)
    value = filters[field_name]
    return value if [Time, ActiveSupport::TimeWithZone, Date, DateTime].include?(value.class)

    DateTime.iso8601(value)
  rescue Date::Error
    result.single_validation_failure!(field: field_name.to_sym, error_code: "invalid_date")
      .raise_if_error!
  end

  # Narrows the scope to records after the cursor position.
  # Subclasses override this to apply a row-value comparison.
  def apply_cursor(scope)
    scope
  end

  # Builds a cursor hash from the last record of the result set.
  # Subclasses override this to return the relevant sort-key values.
  def build_cursor(_record)
  end

  def decode_cursor(encoded)
    JSON.parse(Base64.decode64(encoded)).symbolize_keys
  end

  def encode_cursor(hash)
    Base64.strict_encode64(hash.to_json)
  end

  # Apply consistent ordering across query objects
  def apply_consistent_ordering(scope, default_order: DEFAULT_ORDER)
    scope.order(default_order).order(id: :asc)
  end
end
