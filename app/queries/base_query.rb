# frozen_string_literal: true

class BaseQuery < BaseService
  PER_PAGE = 100

  Pagination = Struct.new(:page, :limit, keyword_init: true) do
    def initialize(page: 0, limit: PER_PAGE)
      super
    end
  end

  class Filters < OpenStruct; end

  def initialize(organization:, pagination: Pagination.new, filters: Filters.new)
    @organization = organization
    @pagination = pagination
    @filters = filters

    super
  end

  private

  attr_reader :organization, :pagination, :filters

  def paginate(scope)
    scope.page(pagination.page).per(pagination.limit)
  end

  def parse_datetime_filter(field_name)
    value = filters[field_name]
    return value if [Time, ActiveSupport::TimeWithZone, Date, DateTime].include?(value.class)

    DateTime.strptime(filters[field_name])
  rescue Date::Error
    result.single_validation_failure!(field: field_name.to_sym, error_code: "invalid_date")
      .raise_if_error!
  end
end
