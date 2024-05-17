# frozen_string_literal: true

class BillableMetricsQuery < BaseQuery
  def call(search_term:, page:, limit:, filters: {})
    @search_term = search_term

    metrics = base_scope.result
    metrics = metrics.where(id: filters[:ids]) if filters[:ids].present?
    metrics = metrics.where(recurring: filters[:recurring]) unless filters[:recurring].nil?
    metrics = metrics.where(aggregation_type: filters[:aggregation_types]) if filters[:aggregation_types].present?
    metrics = metrics.order(created_at: :desc).page(page).per(limit)

    result.billable_metrics = metrics
    result
  end

  private

  attr_reader :search_term

  def base_scope
    BillableMetric.where(organization:).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: 'or',
      name_cont: search_term,
      code_cont: search_term
    }
  end
end
