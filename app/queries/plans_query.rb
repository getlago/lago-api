# frozen_string_literal: true

class PlansQuery < BaseQuery
  def call(search_term:, page:, limit:, filters: {})
    @search_term = search_term

    plans = base_scope.result
    plans = plans.where(id: filters[:ids]) if filters[:ids].present?
    plans = plans.order(created_at: :desc).page(page).per(limit)

    result.plans = plans
    result
  end

  private

  attr_reader :search_term

  def base_scope
    Plan.parents.where(organization:).where(pending_deletion: false).ransack(search_params)
  end

  def search_params
    return nil if search_term.blank?

    {
      m: "or",
      name_cont: search_term,
      code_cont: search_term
    }
  end
end
