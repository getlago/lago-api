# frozen_string_literal: true

class PaymentsQuery < BaseQuery
  Result = BaseResult[:payments]
  Filters = BaseFilters[
    :invoice_id,
    :external_customer_id,
    :currency,
    :payment_status,
    :amount_from,
    :amount_to,
    :receipt_number,
    :created_at_from,
    :created_at_to,
    :payment_provider_type,
    :invoice_number,
    :payment_type,
    :payable_type
  ]

  def call
    return result unless validate_filters.success?

    payments = base_scope
    payments = apply_filters(payments)
    payments = paginate(payments)
    payments = apply_consistent_ordering(payments)

    result.payments = payments
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::PaymentsQueryFiltersContract.new
  end

  def base_scope
    scope = Payment.where.not(customer_id: nil)
      .where(organization:)
      .where.not(payable_id: nil)
      .where(visible_payable_condition)

    return scope if search_term.blank?

    scope.where(id: matching_ids_by_search)
  end

  def matching_ids_by_search
    escaped_term = "%#{Payment.sanitize_sql_like(search_term)}%"
    search_base = Payment.where(organization:)

    branches = [
      search_base.where("payments.provider_payment_id ILIKE ?", escaped_term).select(:id),
      search_base.where("payments.reference ILIKE ?", escaped_term).select(:id)
    ]

    branches << search_base.where(id: search_term).select(:id) if search_term.match?(BaseQuery::UUID_REGEX)

    if filters.invoice_id.blank? && filters.invoice_number.blank?
      branches << search_base.where(payable_type: "Invoice", payable_id: matching_invoice_ids).select(:id)
    end

    if filters.external_customer_id.blank?
      branches << search_base.where(customer_id: matching_customer_ids).select(:id)
    end

    union_sql = branches.map(&:to_sql).join(" UNION ")
    Payment.unscoped.from("(#{union_sql}) AS payments").select(:id)
  end

  def matching_invoice_ids
    escaped_term = "%#{Invoice.sanitize_sql_like(search_term)}%"
    organization.invoices.where("invoices.number ILIKE ?", escaped_term).select(:id)
  end

  def matching_customer_ids
    escaped_term = "%#{Customer.sanitize_sql_like(search_term)}%"

    branches = %i[name firstname lastname external_id email].map do |field|
      organization.customers.where("customers.#{field} ILIKE ?", escaped_term).select(:id)
    end

    union_sql = branches.map(&:to_sql).join(" UNION ")
    Customer.unscoped.from("(#{union_sql}) AS customers").select(:id)
  end

  def visible_payable_condition
    ActiveRecord::Base.sanitize_sql_array([
      <<~SQL.squish,
        CASE payments.payable_type
          WHEN 'Invoice' THEN EXISTS(
            SELECT 1 FROM invoices
            WHERE invoices.id = payments.payable_id
            AND invoices.status IN (:visible_statuses)
            AND organization_id = :organization_id
          )
          ELSE TRUE
        END
      SQL
      {
        visible_statuses: Invoice::VISIBLE_STATUS.values,
        organization_id: organization.id
      }
    ])
  end

  def apply_filters(scope)
    scope = filter_by_invoice(scope) if filters.invoice_id.present?
    scope = filter_by_customer(scope) if filters.external_customer_id.present?
    scope = filter_by_currency(scope) if filters.currency.present?
    scope = with_payment_status(scope) if filters.payment_status.present?
    scope = with_amount_range(scope) if filters.amount_from.present? || filters.amount_to.present?
    scope = with_receipt_number(scope) if filters.receipt_number.present?
    scope = with_created_at_range(scope) if filters.created_at_from.present? || filters.created_at_to.present?
    scope = with_payment_provider_type(scope) if filters.payment_provider_type.present?
    scope = with_invoice_number(scope) if filters.invoice_number.present?
    scope = with_payment_type(scope) if filters.payment_type.present?
    scope = with_payable_type(scope) if filters.payable_type.present?
    scope
  end

  def filter_by_customer(scope)
    # Resolve the customer first so the planner starts from one customer_id instead of a join.
    # Discarded customers stay reachable, as with the belongs_to scope on Payment.
    customer_id = organization.customers.with_discarded.where(external_id: filters.external_customer_id).pick(:id)
    scope.where(customer_id:)
  end

  def filter_by_invoice(scope)
    invoice_id = filters.invoice_id

    scope.joins(<<~SQL.squish)
      LEFT JOIN invoices_payment_requests
        ON invoices_payment_requests.payment_request_id = payments.payable_id
        AND payments.payable_type = 'PaymentRequest'
    SQL
      .where(
        "(payments.payable_type = 'Invoice' AND payments.payable_id = :invoice_id) " \
        "OR invoices_payment_requests.invoice_id = :invoice_id",
        invoice_id:
      )
  end

  def filter_by_currency(scope)
    scope.where(amount_currency: filters.currency)
  end

  def with_payment_status(scope)
    scope.where(payable_payment_status: filters.payment_status)
  end

  def with_amount_range(scope)
    scope = scope.where("payments.amount_cents >= ?::bigint", filters.amount_from) if filters.amount_from.present?
    scope = scope.where("payments.amount_cents <= ?::bigint", filters.amount_to) if filters.amount_to.present?
    scope
  end

  def with_receipt_number(scope)
    # Semi-join on payment_receipts scoped by organization: the receipt is looked up through
    # (organization_id, lower(number)) and the outer query becomes a primary-key lookup,
    # instead of walking every payment of the organization and probing receipts per row.
    receipts = PaymentReceipt.where(organization_id: organization.id)
      .where("lower(payment_receipts.number) = lower(?)", filters.receipt_number)
      .select(:payment_id)
    scope.where(id: receipts)
  end

  def with_created_at_range(scope)
    from = Utils::Datetime.parse_iso8601_date(filters.created_at_from)&.in_time_zone(organization.timezone || "UTC")
    to = Utils::Datetime.parse_iso8601_date(filters.created_at_to)&.in_time_zone(organization.timezone || "UTC")
    scope = scope.where(created_at: from.beginning_of_day..) if from
    scope = scope.where(created_at: ..to.end_of_day) if to
    scope
  end

  def with_payment_provider_type(scope)
    types = Array(filters.payment_provider_type).map { |type| "PaymentProviders::#{type.camelize}Provider" }
    # Resolve provider ids first, scoped to the organization. Deleted providers are kept because
    # historical payments still reference them. An empty list short-circuits to no rows.
    provider_ids = PaymentProviders::BaseProvider.unscoped.where(organization_id: organization.id, type: types).pluck(:id)
    scope.where(payment_provider_id: provider_ids)
  end

  def with_invoice_number(scope)
    # Resolve the invoice ids first (organization-scoped, case-insensitive), then reach the
    # payments through index_payments_on_payable_type_and_payable_id on both payable paths.
    # The ids are passed as literals: with sub-selects the planner turns the OR into hashed
    # SubPlans evaluated against every payment of the organization. No DISTINCT needed:
    # a payment has one payable.
    invoice_ids = organization.invoices.where("lower(invoices.number) = lower(?)", filters.invoice_number).pluck(:id)
    return scope.none if invoice_ids.empty?

    request_ids = PaymentRequest::AppliedInvoice.where(invoice_id: invoice_ids).pluck(:payment_request_id)
    scope.where(
      "(payments.payable_type = 'Invoice' AND payments.payable_id IN (:invoice_ids)) " \
      "OR (payments.payable_type = 'PaymentRequest' AND payments.payable_id IN (:request_ids))",
      invoice_ids:, request_ids: request_ids.presence || [nil]
    )
  end

  def with_payment_type(scope)
    scope.where(payment_type: filters.payment_type)
  end

  def with_payable_type(scope)
    scope.where(payable_type: filters.payable_type)
  end
end
