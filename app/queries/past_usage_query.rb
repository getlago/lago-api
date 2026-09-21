# frozen_string_literal: true

class PastUsageQuery < BaseQuery
  Result = BaseResult[:usage_periods, :current_page, :next_page, :prev_page, :total_pages, :total_count]
  Filters = BaseFilters[:external_customer_id, :external_subscription_id, :periods_count, :billable_metric_code]

  UsagePeriods = Data.define(:invoice_subscription, :fees)

  def call
    validate_filters
    return result if result.error.present?

    query_result = apply_consistent_ordering(query)
    free_usage_fees = free_fees_by_period(query_result.to_a)
    result.usage_periods = query_result.map do |invoice_subscription|
      UsagePeriods.new(
        invoice_subscription:,
        fees: fees_query(invoice_subscription) + free_usage_fees.fetch(invoice_subscription.id, [])
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

    scope.where(invoice_id: invoice_subscription.invoice_id).to_a
  end

  def free_fees_by_period(invoice_subscriptions)
    return {} if invoice_subscriptions.empty?

    charge_ids = regroup_charge_ids(invoice_subscriptions)
    return {} if charge_ids.empty?

    owner_ids = free_usage_period_ids(invoice_subscriptions, charge_ids)
    page_ids = invoice_subscriptions.map(&:id).to_set
    owned_keys = owner_ids.select { |_key, owner_id| page_ids.include?(owner_id) }.keys
    if owned_keys.empty?
      {}
    else
      free_fees(owned_keys, charge_ids).group_by do |fee|
        owner_ids[[fee.subscription_id, fee.properties["charges_from_datetime"]]]
      end
    end
  end

  def regroup_charge_ids(invoice_subscriptions)
    subscription_ids = invoice_subscriptions.map(&:subscription_id).uniq
    scope = Charge.with_discarded
      .where(plan_id: Subscription.where(id: subscription_ids).select(:plan_id))
      .where(pay_in_advance: true, invoiceable: false, regroup_paid_fees: :invoice)
    if filters.billable_metric_code
      scope = scope.where(billable_metric_id: billable_metric.id)
    end

    scope.pluck(:id)
  end

  def free_fees(keys, charge_ids)
    Fee.where(organization:, charge_id: charge_ids, invoice_id: nil, pay_in_advance: true, amount_cents: 0)
      .charge.positive_units
      .merge(fee_period_conditions(keys))
      .includes(:charge_filter, :presentation_breakdowns)
  end

  # A free fee is shown next to the regrouped paid fees of its own period, on the
  # invoice they were regrouped on. When none were regrouped yet, it is shown on the
  # regular invoice of the period. Owners are resolved for the whole page, including
  # invoices outside it, so a fee is never counted on two pages.
  def free_usage_period_ids(periods, charge_ids)
    regrouped = regrouped_period_keys(periods.map { |period| usage_period_key(period) }, charge_ids)

    conditions = periods.map do |period|
      InvoiceSubscription.where(
        subscription_id: period.subscription_id,
        charges_from_datetime: period.charges_from_datetime,
        invoicing_reason: [:subscription_periodic, :subscription_terminating]
      )
    end.reduce { |scope, condition| scope.or(condition) }
    if regrouped.any?
      conditions = conditions.or(
        InvoiceSubscription.where(invoice_id: regrouped.keys, subscription_id: periods.map(&:subscription_id).uniq)
      )
    end

    rows = InvoiceSubscription.where(organization:, regenerated_invoice_id: nil)
      .merge(conditions)
      .select(:id, :invoice_id, :subscription_id, :charges_from_datetime, :invoicing_reason)
      .order(:created_at, :id)
      .to_a

    owners = {}
    rows.each do |row|
      regrouped.fetch(row.invoice_id, []).each do |key|
        owners[key] ||= row.id if key.first == row.subscription_id
      end
    end
    rows.each do |row|
      next unless row.subscription_periodic? || row.subscription_terminating?

      owners[usage_period_key(row)] ||= row.id
    end
    owners
  end

  def regrouped_period_keys(keys, charge_ids)
    Fee.where(organization:, charge_id: charge_ids).where.not(invoice_id: nil).charge
      .merge(fee_period_conditions(keys))
      .distinct
      .pluck(:invoice_id, :subscription_id, Arel.sql("fees.properties ->> 'charges_from_datetime'"))
      .group_by(&:first)
      .transform_values { |rows| rows.map { |_, subscription_id, period_start| [subscription_id, period_start] } }
  end

  # Match on the period start only: a fee keeps the period end known when it was
  # created, which outlives the invoice boundaries when the subscription is
  # terminated mid-period.
  def fee_period_conditions(keys)
    keys.map do |subscription_id, period_start|
      Fee.where(subscription_id:).where("fees.properties ->> 'charges_from_datetime' = ?", period_start)
    end.reduce { |scope, condition| scope.or(condition) }
  end

  # Fee boundaries are serialized as UTC ISO 8601 with milliseconds.
  def usage_period_key(period)
    [period.subscription_id, period.charges_from_datetime.utc.iso8601(3)]
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
