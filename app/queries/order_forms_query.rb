# frozen_string_literal: true

class OrderFormsQuery < BaseQuery
  Result = BaseResult[:order_forms]
  Filters = BaseFilters[:status, :external_customer_id]

  def call
    return result unless validate_filters.success?

    order_forms = base_scope.result
    order_forms = with_status(order_forms) if filters.status.present?
    order_forms = with_external_customer_id(order_forms) if filters.external_customer_id.present?
    order_forms = paginate(order_forms)
    order_forms = apply_consistent_ordering(order_forms)

    result.order_forms = order_forms
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::OrderFormsQueryFiltersContract.new
  end

  def base_scope
    organization.order_forms.ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      number_cont: search_term
    }
  end

  def with_status(scope)
    scope.where(status: filters.status)
  end

  def with_external_customer_id(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end
end
