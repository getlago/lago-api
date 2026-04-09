# frozen_string_literal: true

class QuoteVersionsQuery < BaseQuery
  Result = BaseResult[:quote_versions]
  Filters = BaseFilters[:customers, :statuses, :numbers, :from_date, :to_date, :owners]

  def call
    return result unless validate_filters.success?

    quote_versions = base_scope
    quote_versions = with_customer(quote_versions) if filters.customers.present?
    quote_versions = with_number(quote_versions) if filters.numbers.present?
    quote_versions = with_status(quote_versions) if filters.statuses.present?
    quote_versions = with_date(quote_versions) if filters.from_date.present? || filters.to_date.present?
    quote_versions = with_owners(quote_versions) if filters.owners.present?

    # final ordering and pagination
    quote_versions = quote_versions.order(created_at: :desc)
    quote_versions = paginate(quote_versions)

    result.quote_versions = quote_versions
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::QuoteVersionsQueryFiltersContract.new
  end

  def base_scope
    QuoteVersion.where(organization:)
  end

  def with_customer(scope)
    scope.joins(:quote).where(quotes: {customer_id: filters.customers})
  end

  def with_status(scope)
    scope.where(status: filters.statuses)
  end

  def with_number(scope)
    scope.joins(:quote).where(quotes: {number: filters.numbers})
  end

  def with_date(scope)
    scope.where(created_at: filters.from_date..filters.to_date)
  end

  def with_owners(scope)
    quote_ids = Quote
      .joins(:quote_owners)
      .where(
        organization:,
        quote_owners: {user_id: filters.owners}
      )
      .select(:id)
      .distinct

    scope.where(quote_id: quote_ids)
  end
end
