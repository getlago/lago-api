# frozen_string_literal: true

class PastUsageQuery < BaseQuery
  Result = BaseResult[:usage_periods, :current_page, :next_page, :prev_page, :total_pages, :total_count]
  Filters = BaseFilters[:external_customer_id, :external_subscription_id, :periods_count, :billable_metric_code]

  UsagePeriods = Data.define(:invoice_subscription, :fees)

  def call
    validate_filters
    return result if result.error.present?

    query_result = apply_consistent_ordering(query)
    result.usage_periods = query_result.map do |invoice_subscription|
      UsagePeriods.new(
        invoice_subscription:,
        fees: fees_query(invoice_subscription)
      )
    end

    # NOTE: Pagination attributes
    if pagination
      result.current_page = query_result.current_page
      result.next_page = query_result.next_page
      result.prev_page = query_result.prev_page
      result.total_pages = query_result.total_pages
      result.total_count = query_result.total_count
    end

    result
  end

  private

  def query
    base_query = InvoiceSubscription.joins(subscription: :customer)
      .where.not(charges_from_datetime: nil)
      .where(customers: {external_id: filters.external_customer_id, organization_id: organization.id})
      .where(subscriptions: {external_id: filters.external_subscription_id})
      .order(charges_from_datetime: :desc)
      .includes(:invoice)

    base_query = paginate(base_query)
    base_query = base_query.limit(filters.periods_count.to_i) if filters.periods_count
    base_query
  end

  def fees_query(invoice_subscription)
    scope = Fee.joins(:subscription)
      .where(subscription: {external_id: filters.external_subscription_id})
      .charge.includes(:charge_filter, :presentation_breakdowns)
    if filters.billable_metric_code
      scope = scope.joins(:charge).where(charges: {billable_metric_id: billable_metric.id})
    end

    # Keep these lookups separate so invoice and subscription indexes can bound each query.
    fees = scope.where(invoice_id: invoice_subscription.invoice_id).to_a
    if free_usage_period?(invoice_subscription)
      fees.concat(scope.merge(free_fees(invoice_subscription)).to_a)
    end

    fees
  end

  def free_fees(invoice_subscription)
    # Free advance fees retain metered units but can stay pending and never join
    # the paid-fee invoice. Recover them using their original billing period.
    # JSON fee boundaries have millisecond precision; invoice boundaries have microseconds.
    Fee.where(organization:, subscription_id: invoice_subscription.subscription_id, invoice_id: nil,
      pay_in_advance: true, amount_cents: 0, precise_amount_cents: 0)
      .charge.positive_units.joins(:charge)
      .where(charges: {pay_in_advance: true, invoiceable: false, regroup_paid_fees: :invoice})
      .where("(fees.properties ->> 'charges_from_datetime')::timestamptz = ?", invoice_subscription.charges_from_datetime.iso8601(3))
      .where("(fees.properties ->> 'charges_to_datetime')::timestamptz = ?", invoice_subscription.charges_to_datetime.iso8601(3))
  end

  def free_usage_period?(invoice_subscription)
    # Prefer the regrouped invoice, falling back to the regular invoice for an
    # entirely free period. Choose outside pagination so fees appear only once.
    @free_usage_period_ids ||= {}
    key = [invoice_subscription.subscription_id, invoice_subscription.charges_from_datetime, invoice_subscription.charges_to_datetime]
    period_id = @free_usage_period_ids.fetch(key) do
      @free_usage_period_ids[key] = InvoiceSubscription.where(
        organization:,
        subscription_id: invoice_subscription.subscription_id,
        charges_from_datetime: invoice_subscription.charges_from_datetime,
        charges_to_datetime: invoice_subscription.charges_to_datetime,
        invoicing_reason: [:in_advance_charge_periodic, :subscription_periodic, :subscription_terminating]
      ).order(Arel.sql("CASE WHEN invoicing_reason = 'in_advance_charge_periodic' THEN 0 ELSE 1 END"), :created_at, :id).pick(:id)
    end

    invoice_subscription.id == period_id
  end

  def validate_filters
    if filters.external_customer_id.blank?
      return result.single_validation_failure!(
        field: :external_customer_id,
        error_code: "value_is_mandatory"
      )
    end

    if filters.external_subscription_id.blank?
      return result.single_validation_failure!(
        field: :external_subscription_id,
        error_code: "value_is_mandatory"
      )
    end

    return if filters.billable_metric_code.blank?

    result.not_found_failure!(resource: "billable_metric") if billable_metric.blank?
  end

  def billable_metric
    @billable_metric ||= organization.billable_metrics.find_by(code: filters.billable_metric_code)
  end
end
