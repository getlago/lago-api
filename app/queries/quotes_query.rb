# frozen_string_literal: true

class QuotesQuery < BaseQuery
  Result = BaseResult[:quotes]

  def call
    quotes = base_scope.order(number: :desc, version: :desc)
    quotes = paginate(quotes)

    result.quotes = quotes
    result
  end

  private

  def base_scope
    Quote.where(organization:)
  end
end
