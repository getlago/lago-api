# frozen_string_literal: true

class BillableMetricsQuery < BaseQuery
  def call
    return result unless validate_filters.success?

    metrics = base_scope.result
    metrics = paginate(metrics)
    metrics = metrics.order(created_at: :desc)

    metrics = with_recurring(metrics) unless filters.recurring.nil?
    metrics = with_aggregation_type(metrics) if filters.aggregation_types.present?

    result.billable_metrics = metrics
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
      m: 'or',
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
end
