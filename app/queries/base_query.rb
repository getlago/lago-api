# frozen_string_literal: true

class BaseQuery < BaseService
  # nil values force Kaminari to apply its default values for page and limit.
  DEFAULT_PAGINATION_PARAMS = {page: nil, limit: nil}

  Pagination = Struct.new(:page, :limit, keyword_init: true)

  class Filters < OpenStruct; end

  def initialize(organization:, pagination: DEFAULT_PAGINATION_PARAMS, filters: Filters.new)
    @organization = organization
    @pagination_params = pagination
    @filters = filters

    super
  end

  private

  attr_reader :organization, :pagination_params, :filters

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
    return value if [Time, ActiveSupport::TimeWithZone, Date, DateTime].include?(value.class)

    DateTime.strptime(value)
  rescue Date::Error
    result.single_validation_failure!(field: field_name.to_sym, error_code: 'invalid_date')
      .raise_if_error!
  end
end
