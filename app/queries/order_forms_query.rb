# frozen_string_literal: true

class OrderFormsQuery < BaseQuery
  Result = BaseResult[:order_forms]
  Filters = BaseFilters[
    :status,
    :external_customer_id,
    :number,
    :customer_id,
    :owner_id,
    :quote_number,
    :order_form_date_from,
    :order_form_date_to,
    :expiry_date_from,
    :expiry_date_to
  ]

  def call
    return result unless validate_filters.success?

    order_forms = base_scope.result
    order_forms = with_status(order_forms) if filters.status.present?
    order_forms = with_external_customer_id(order_forms) if filters.external_customer_id.present?
    order_forms = with_number(order_forms) if filters.number.present?
    order_forms = with_customer_id(order_forms) if filters.customer_id.present?
    order_forms = with_owner_id(order_forms) if filters.owner_id.present?
    order_forms = with_quote_number(order_forms) if filters.quote_number.present?
    order_forms = with_order_form_date_range(order_forms) if filters.order_form_date_from || filters.order_form_date_to
    order_forms = with_expiry_date_range(order_forms) if filters.expiry_date_from || filters.expiry_date_to
    order_forms = paginate(order_forms)
    order_forms = apply_consistent_ordering(order_forms)

    result.order_forms = order_forms
    result
  rescue BaseService::FailedResult
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

  def with_number(scope)
    scope.where(number: filters.number)
  end

  def with_customer_id(scope)
    scope.where(customer_id: filters.customer_id)
  end

  def with_owner_id(scope)
    scope.joins(quote: :quote_owners).where(quote_owners: {user_id: filters.owner_id})
  end

  def with_quote_number(scope)
    scope.joins(:quote).where(quotes: {number: filters.quote_number})
  end

  def with_order_form_date_range(scope)
    scope = scope.where(created_at: order_form_date_from..) if filters.order_form_date_from
    scope = scope.where(created_at: ..order_form_date_to) if filters.order_form_date_to
    scope
  end

  def with_expiry_date_range(scope)
    scope = scope.where(expires_at: expiry_date_from..) if filters.expiry_date_from
    scope = scope.where(expires_at: ..expiry_date_to) if filters.expiry_date_to
    scope
  end

  def order_form_date_from
    @order_form_date_from ||= parse_datetime_filter(:order_form_date_from)
  end

  def order_form_date_to
    @order_form_date_to ||= parse_datetime_filter(:order_form_date_to)
  end

  def expiry_date_from
    @expiry_date_from ||= parse_datetime_filter(:expiry_date_from)
  end

  def expiry_date_to
    @expiry_date_to ||= parse_datetime_filter(:expiry_date_to)
  end
end
