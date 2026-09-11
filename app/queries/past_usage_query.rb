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

    owner_ids = free_usage_period_ids(invoice_subscriptions)
    periods_by_id = invoice_subscriptions.index_by(&:id)
    periods = owner_ids.values.filter_map { |id| periods_by_id[id] }
    if periods.empty?
      {}
    else
      free_fees(periods).group_by do |fee|
        owner_ids[usage_period_key(fee.subscription_id, fee.properties["charges_from_datetime"], fee.properties["charges_to_datetime"])]
      end
    end
  end

  def free_fees(periods)
    # Match all requested periods in one scan of standalone fees. JSON boundaries
    # have millisecond precision; invoice boundaries have microseconds.
    conditions = periods.map do |period|
      Fee.where(subscription_id: period.subscription_id)
        .where("(fees.properties ->> 'charges_from_datetime')::timestamptz = ?", period.charges_from_datetime.iso8601(3))
        .where("(fees.properties ->> 'charges_to_datetime')::timestamptz = ?", period.charges_to_datetime.iso8601(3))
    end.reduce { |scope, condition| scope.or(condition) }

    scope = Fee.where(organization:, subscription_id: periods.map(&:subscription_id).uniq, invoice_id: nil,
      pay_in_advance: true, amount_cents: 0, precise_amount_cents: 0)
      .charge.positive_units.joins(:charge)
      .where(charges: {pay_in_advance: true, invoiceable: false, regroup_paid_fees: :invoice})
      .merge(conditions)
      .includes(:charge_filter, :presentation_breakdowns)

    if filters.billable_metric_code
      scope = scope.where(charges: {billable_metric_id: billable_metric.id})
    end

    scope
  end

  def free_usage_period_ids(periods)
    # Resolve owners for the whole page, including competing invoices outside it.
    # Prefer regrouped invoices, then regular invoices for entirely free periods.
    conditions = periods.map do |period|
      InvoiceSubscription.where(
        subscription_id: period.subscription_id,
        charges_from_datetime: period.charges_from_datetime,
        charges_to_datetime: period.charges_to_datetime
      )
    end.reduce { |scope, condition| scope.or(condition) }

    InvoiceSubscription.where(organization:,
      invoicing_reason: [:in_advance_charge_periodic, :subscription_periodic, :subscription_terminating])
      .merge(conditions)
      .select(:id, :subscription_id, :charges_from_datetime, :charges_to_datetime)
      .order(Arel.sql("CASE WHEN invoicing_reason = 'in_advance_charge_periodic' THEN 0 ELSE 1 END"), :created_at, :id)
      .each_with_object({}) do |period, owners|
        key = usage_period_key(period.subscription_id, period.charges_from_datetime, period.charges_to_datetime)
        owners[key] ||= period.id
      end
  end

  def usage_period_key(subscription_id, from_datetime, to_datetime)
    [subscription_id, from_datetime.to_time.getutc.iso8601(3), to_datetime.to_time.getutc.iso8601(3)]
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
