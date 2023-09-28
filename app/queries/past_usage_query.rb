# frozen_string_literal: true

class PastUsageQuery < BaseQuery
  def call
    validate_filters
    return result if result.error.present?

    result.usage = query.map do |invoice_subscription|
      OpenStruct.new(
        invoice_subscription:,
        fees: fees_query(invoice_subscription.invoice),
      )
    end

    result
  end

  private

  def query
    base_query = InvoiceSubscription.joins(subscription: :customer)
      .where(customers: { external_id: filters.external_customer_id, organization_id: organization.id })
      .where(subscriptions: { external_id: filters.external_subscription_id })
      .order(from_datetime: :desc)
      .includes(:invoice)

    base_query = paginate(base_query)
    base_query = base_query.limit(filters.periods_count) if filters.periods_count
    base_query
  end

  def fees_query(invoice)
    query = invoice.fees.charge
    return query unless filters.billable_metric_code

    query.joins(:charge).where(charges: { billable_metric_id: billable_metric.id })
  end

  def validate_filters
    if filters.external_customer_id.blank?
      return result.single_validation_failure!(
        field: :external_customer_id,
        error_code: 'value_is_mandatory',
      )
    end

    if filters.external_subscription_id.blank?
      return result.single_validation_failure!(
        field: :external_subscription_id,
        error_code: 'value_is_mandatory',
      )
    end

    return if filters.billable_metric_code.blank?

    result.not_found_failure!(resource: 'billable_metric') if billable_metric.blank?
  end

  def billable_metric
    @billable_metric ||= organization.billable_metrics.find_by(code: filters.billable_metric_code)
  end
end
