# frozen_string_literal: true

class BillableMetricsQuery < BaseQuery
  Result = BaseResult[:billable_metrics]
  Filters = BaseFilters[:organization_id, :recurring, :aggregation_types, :plan_id, :created_at_from, :created_at_to]

  def call
    return result unless validate_filters.success?

    metrics = base_scope.result
    metrics = with_recurring(metrics) unless filters.recurring.nil?
    metrics = with_aggregation_type(metrics) if filters.aggregation_types.present?

    metrics = with_plan(metrics) if filters.plan_id.present?
    metrics = with_date_range(metrics, :created_at)
    metrics = apply_consistent_ordering(metrics)
    metrics = paginate(metrics)

    result.billable_metrics = metrics
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::BillableMetricsQueryFiltersContract.new
  end

  def base_scope
    BillableMetric.where(organization:).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end

  def with_recurring(scope)
    scope.where(recurring: filters.recurring)
  end

  def with_aggregation_type(scope)
    scope.where(aggregation_type: filters.aggregation_types)
  end

  def with_plan(scope)
    scope.joins(:charges).where(charges: {plan_id: filters.plan_id}).distinct
  end
end
