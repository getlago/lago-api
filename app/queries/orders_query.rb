# frozen_string_literal: true

class OrdersQuery < BaseQuery
  Result = BaseResult[:orders]
  Filters = BaseFilters[:status, :order_type, :external_customer_id]

  def call
    return result unless validate_filters.success?

    orders = base_scope.result
    orders = with_status(orders) if filters.status.present?
    orders = with_order_type(orders) if filters.order_type.present?
    orders = with_external_customer_id(orders) if filters.external_customer_id.present?
    orders = paginate(orders)
    orders = apply_consistent_ordering(orders)

    result.orders = orders
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::OrdersQueryFiltersContract.new
  end

  def base_scope
    organization.orders.ransack(search_params)
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

  def with_order_type(scope)
    scope.where(order_type: filters.order_type)
  end

  def with_external_customer_id(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end
end
