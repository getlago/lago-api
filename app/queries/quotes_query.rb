# frozen_string_literal: true

class QuotesQuery < BaseQuery
  attr_reader :latest_version_only

  Result = BaseResult[:quotes]
  Filters = BaseFilters[:customer, :status, :number, :version, :from_date, :to_date, :owners]

  def initialize(latest_version_only:, **args)
    @latest_version_only = latest_version_only
    super(**args)
  end

  def call
    return result unless validate_filters.success?

    quotes = base_scope
    quotes = paginate(quotes)

    quotes = with_customer(quotes) if filters.customer.present?
    quotes = with_number(quotes) if filters.number.present?
    quotes = with_status(quotes) if filters.status.present?
    quotes = with_version(quotes) if filters.version.present?
    quotes = with_date(quotes) if filters.from_date.present? || filters.to_date.present?
    quotes = with_owners(quotes) if filters.owners.present?
    quotes = with_latest_version_only(quotes) if latest_version_only
    quotes = quotes.order(created_at: :desc)

    result.quotes = quotes
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::QuotesQueryFiltersContract.new
  end

  def base_scope
    Quote.where(organization:)
  end

  def with_customer(scope)
    scope.where(customer_id: filters.customer)
  end

  def with_status(scope)
    scope.where(status: filters.status)
  end

  def with_number(scope)
    scope.where(number: filters.number)
  end

  def with_version(scope)
    scope.where(version: filters.version)
  end

  def with_date(scope)
    scope.where(created_at: filters.from_date..filters.to_date)
  end

  def with_owners(scope)
    scope.joins(:quote_owners).where(quote_owners: {user_id: filters.owners})
  end

  def with_latest_version_only(scope)
    scope.select("DISTINCT ON (sequential_id) *").order(:sequential_id, version: :desc)
  end
end
