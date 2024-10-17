# frozen_string_literal: true

class FeesQuery < BaseQuery
  def call
    fees = paginate(Fee.from_organization(organization))
    fees = fees.order(created_at: :asc, id: :asc)

    fees = with_external_subscription(fees) if filters.external_subscription_id
    fees = with_external_customer(fees) if filters.external_customer_id

    fees = fees.where(amount_currency: filters.currency.upcase) if filters.currency
    fees = with_billable_metric_code(fees) if filters.billable_metric_code

    fees = with_fee_type(fees) if filters.fee_type
    fees = with_payment_status(fees) if filters.payment_status

    fees = fees.where(pay_in_advance_event_transaction_id: filters.event_transaction_id) if filters.event_transaction_id

    fees = with_created_date_range(fees) if filters.created_at_from || filters.created_at_to
    fees = with_succeeded_date_range(fees) if filters.succeeded_at_from || filters.succeeded_at_to
    fees = with_failed_date_range(fees) if filters.failed_at_from || filters.failed_at_to
    fees = with_refunded_date_range(fees) if filters.refunded_at_from || filters.refunded_at_to

    result.fees = fees
    result
  rescue BaseService::FailedResult
    result
  end

  def with_external_subscription(scope)
    scope.joins(:subscription).where(subscription: {external_id: filters.external_subscription_id})
  end

  def with_external_customer(scope)
    # NOTE: pay_in_advance fees are not be linked to any invoice, but add_on fees does not have any subscriptions
    #       so we need a bit of logic to find the fee in the right customer scope
    #       - Add ons and regular fees: customers linked to the invoice
    #       - Instant: customers linked to the subscription
    scope
      .joins('LEFT JOIN customers AS invoice_customers ON invoice_customers.id = invoices.customer_id')
      .where('COALESCE(customers.external_id, invoice_customers.external_id) = ?', filters.external_customer_id)
  end

  def with_billable_metric_code(scope)
    scope.joins(:billable_metric)
      .where(billable_metric: {code: filters.billable_metric_code})
  end

  def with_fee_type(scope)
    unless Fee::FEE_TYPES.include?(filters.fee_type.to_sym)
      result.single_validation_failure!(field: :fee_type, error_code: 'value_is_invalid')
        .raise_if_error!
    end

    scope.where(fee_type: filters.fee_type)
  end

  def with_payment_status(scope)
    unless Fee::PAYMENT_STATUS.include?(filters.payment_status.to_sym)
      result.single_validation_failure!(field: :payment_status, error_code: 'value_is_invalid')
        .raise_if_error!
    end

    scope.where(payment_status: filters.payment_status)
  end

  def with_created_date_range(scope)
    scope = scope.where(created_at: created_at_from..) if filters.created_at_from
    scope = scope.where(created_at: ..created_at_to) if filters.created_at_to
    scope
  end

  def created_at_from
    @created_at_from ||= parse_datetime_filter(:created_at_from)
  end

  def created_at_to
    @created_at_to ||= parse_datetime_filter(:created_at_to)
  end

  def with_succeeded_date_range(scope)
    scope = scope.where(succeeded_at: succeeded_at_from..) if filters.succeeded_at_from
    scope = scope.where(succeeded_at: ..succeeded_at_to) if filters.succeeded_at_to
    scope
  end

  def succeeded_at_from
    @succeeded_at_from ||= parse_datetime_filter(:succeeded_at_from)
  end

  def succeeded_at_to
    @succeeded_at_to ||= parse_datetime_filter(:succeeded_at_to)
  end

  def with_failed_date_range(scope)
    scope = scope.where(failed_at: failed_at_from..) if filters.failed_at_from
    scope = scope.where(failed_at: ..failed_at_to) if filters.failed_at_to
    scope
  end

  def failed_at_from
    @failed_at_from ||= parse_datetime_filter(:failed_at_from)
  end

  def failed_at_to
    @failed_at_to ||= parse_datetime_filter(:failed_at_to)
  end

  def with_refunded_date_range(scope)
    scope = scope.where(refunded_at: refunded_at_from..) if filters.refunded_at_from
    scope = scope.where(refunded_at: ..refunded_at_to) if filters.refunded_at_to
    scope
  end

  def refunded_at_from
    @refunded_at_from ||= parse_datetime_filter(:refunded_at_from)
  end

  def refunded_at_to
    @refunded_at_to ||= parse_datetime_filter(:refunded_at_to)
  end
end
