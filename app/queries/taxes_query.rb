# frozen_string_literal: true

class TaxesQuery < BaseQuery
  Result = BaseResult[:taxes]
  Filters = BaseFilters[:auto_generated, :applied_to_organization]

  DEFAULT_ORDER = "name"

  def call
    taxes = base_scope.result
    taxes = taxes.preload(:billing_entities) unless pagination.is_a?(CursorPagination::Cursor)

    taxes = with_auto_generated(taxes) if filters.auto_generated.present?
    taxes = with_applied_to_organization(taxes) unless filters.applied_to_organization.nil?

    taxes = taxes.order(order)
    taxes = apply_consistent_ordering(taxes)

    result.taxes = paginate(taxes)
    result
  end

  private

  def base_scope
    Tax.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
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
    applied = scope.applied_to_billing_entity(organization.default_billing_entity)
    if filters.applied_to_organization
      applied
    else
      scope.where.not(id: applied)
    end
  end
end
