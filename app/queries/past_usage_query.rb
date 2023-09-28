# frozen_string_literal: true

class PastUsageQuery < BaseQuery
  def call
    validate_filters
    return result if result.error.present?

    result.usage = query
    result
  end

  private

  def query
    base_query = InvoiceSubscription.joins(subscription: :customer)
      .where(customers: { external_id: filters.external_customer_id, organization_id: organization.id })
      .where(subscriptions: { external_id: filters.external_subscription_id })
      .order(from_datetime: :desc)
      .includes(:invoice)

    paginate(base_query)
  end

  def validate_filters
    if filters.external_customer_id.blank?
      return result.single_validation_failure!(
        field: :external_customer_id,
        error_code: 'value_is_mandatory',
      )
    end

    return if filters.external_subscription_id.present?

    result.single_validation_failure!(
      field: :external_subscription_id,
      error_code: 'value_is_mandatory',
    )
  end
end
