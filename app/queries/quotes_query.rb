# frozen_string_literal: true

class QuotesQuery < BaseQuery
  Result = BaseResult[:quotes]
  Filters = BaseFilters[:customers, :numbers, :statuses, :from_date, :to_date, :owners]

  def call
    return result unless validate_filters.success?

    quotes = base_scope
    quotes = with_customer(quotes) if filters.customers.present?
    quotes = with_number(quotes) if filters.numbers.present?
    quotes = with_status(quotes) if filters.statuses.present?
    quotes = with_date(quotes) if filters.from_date.present? || filters.to_date.present?
    quotes = with_owners(quotes) if filters.owners.present?

    # final ordering and pagination
    quotes = quotes.order(created_at: :desc)
    quotes = paginate(quotes)

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
    scope.where(customer_id: filters.customers)
  end

  def with_number(scope)
    scope.where(number: filters.numbers)
  end

  def with_status(scope)
    scope.joins(:current_version).where(quote_versions: {status: filters.statuses})
  end

  def with_date(scope)
    scope.where(created_at: filters.from_date..filters.to_date)
  end

  def with_owners(scope)
    quote_ids = QuoteOwner
      .where(
        organization:,
        user_id: filters.owners
      )
      .select(:quote_id)
      .distinct

    scope.where(id: quote_ids)
  end
end
