# frozen_string_literal: true

class TaxesQuery < BaseQuery
  def call(search_term:, page:, limit:, order:, filters: {})
    @search_term = search_term

    taxes = base_scope.result
    taxes = taxes.where(id: filters[:ids]) if filters[:ids].present?
    taxes = taxes.where(auto_generated: filters[:auto_generated]) if filters[:auto_generated].present?

    unless filters[:applied_to_organization].nil?
      taxes = taxes.where(applied_to_organization: filters[:applied_to_organization])
    end

    order = order.presence || :name
    taxes = taxes.order(order).page(page).per(limit)

    result.taxes = taxes
    result
  end

  private

  attr_reader :search_term

  def base_scope
    Tax.where(organization:).ransack(search_params)
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
