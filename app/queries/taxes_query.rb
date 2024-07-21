# frozen_string_literal: true

class TaxesQuery < BaseQuery
  DEFAULT_ORDER = 'name'

  def call
    taxes = base_scope.result
    taxes = paginate(taxes)
    taxes = taxes.order(order)

    taxes = with_auto_generated(taxes) if filters.auto_generated.present?
    taxes = with_applied_to_organization(taxes) unless filters.applied_to_organization.nil?

    result.taxes = taxes
    result
  end

  private

  def base_scope
    Tax.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: 'or',
      name_cont: search_term,
      code_cont: search_term
    }
  end

  def order
    Tax::ORDERS.include?(@order) ? @order : DEFAULT_ORDER
  end

  def with_auto_generated(scope)
    scope.where(auto_generated: filters.auto_generated)
  end

  def with_applied_to_organization(scope)
    scope.where(applied_to_organization: filters.applied_to_organization)
  end
end
