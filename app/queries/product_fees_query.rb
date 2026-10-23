# frozen_string_literal: true

class ProductFeesQuery < BaseQuery
  Result = BaseResult[:fees]
  Filters = BaseFilters[
    :lago_invoice_id,
    :payment_status,
    :external_customer_id,
    :external_contract_id,
    :currency,
    :event_transaction_id,
    :created_at_from,
    :created_at_to,
    :succeeded_at_from,
    :succeeded_at_to,
    :failed_at_from,
    :failed_at_to,
    :refunded_at_from,
    :refunded_at_to
  ]

  DATE_RANGES = %i[created_at succeeded_at failed_at refunded_at].freeze

  def call
    fees = Fee.where(organization:).product
    fees = apply_consistent_ordering(fees)

    fees = with_invoice(fees) if filters.lago_invoice_id.present?
    fees = with_payment_status(fees) if filters.payment_status.present?
    fees = with_external_customer(fees) if filters.external_customer_id.present?
    fees = with_external_contract(fees) if filters.external_contract_id.present?
    fees = with_currency(fees) if filters.currency.present?
    fees = fees.where(pay_in_advance_event_transaction_id: filters.event_transaction_id) if filters.event_transaction_id.present?

    DATE_RANGES.each { |column| fees = with_date_range(fees, column) }

    result.fees = paginate(fees)
    result
  rescue BaseService::FailedResult
    result
  end

  private

  # Checked first: the uuid column casts any other string to NULL, which would match the fees not invoiced yet.
  def with_invoice(scope)
    invalid_filter!(:lago_invoice_id) unless filters.lago_invoice_id.is_a?(String) && filters.lago_invoice_id.match?(UUID_REGEX)

    scope.where(invoice_id: filters.lago_invoice_id)
  end

  def with_payment_status(scope)
    invalid_filter!(:payment_status) unless Fee::PAYMENT_STATUS.map(&:to_s).include?(filters.payment_status)

    scope.where(payment_status: filters.payment_status)
  end

  def with_currency(scope)
    invalid_filter!(:currency) unless filters.currency.is_a?(String)

    scope.where(amount_currency: filters.currency.upcase)
  end

  # Through the contract rather than the invoice: a fee billed on an event has no invoice yet.
  # Product fees billed before contracts carry their customer through the subscription or the invoice.
  def with_external_customer(scope)
    # Discarded too: a deleted customer's fees stay billed and findable.
    customer_ids = Customer.with_discarded.where(organization:, external_id: filters.external_customer_id).select(:id)
    without_contract = scope.where(contract_id: nil)

    scope.where(contract_id: organization.contracts.where(customer_id: customer_ids).select(:id))
      .or(without_contract.where(subscription_id: Subscription.where(organization:, customer_id: customer_ids).select(:id)))
      .or(without_contract.where(invoice_id: Invoice.where(organization:, customer_id: customer_ids).select(:id)))
  end

  def with_external_contract(scope)
    scope.where(contract_id: organization.contracts.where(external_id: filters.external_contract_id).select(:id))
  end

  def invalid_filter!(field)
    result.single_validation_failure!(field:, error_code: "value_is_invalid").raise_if_error!
  end

  def with_date_range(scope, column)
    from = filters[:"#{column}_from"]
    to = filters[:"#{column}_to"]

    scope = scope.where(column => parse_datetime_filter(:"#{column}_from")..) if from.present?
    scope = scope.where(column => ..parse_datetime_filter(:"#{column}_to")) if to.present?
    scope
  end
end
