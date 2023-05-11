# frozen_string_literal: true

class TaxRatesQuery < BaseQuery
  def call(search_term:, page:, limit:, filters: {})
    @search_term = search_term

    tax_rates = base_scope.result
    tax_rates = tax_rates.where(id: filters[:ids]) if filters[:ids].present?

    unless filters[:applied_by_default].nil?
      tax_rates = tax_rates.where(applied_by_default: filters[:applied_by_default])
    end

    tax_rates = tax_rates.order(:name).page(page).per(limit)

    result.tax_rates = tax_rates
    result
  end

  private

  attr_reader :search_term

  def base_scope
    TaxRate.where(organization:).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      name_cont: search_term,
      code_cont: search_term,
    }
  end
end
