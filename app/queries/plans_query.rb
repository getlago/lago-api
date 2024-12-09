# frozen_string_literal: true

class PlansQuery < BaseQuery
  def call
    plans = base_scope.result
    plans = paginate(plans)
    plans = apply_consistent_ordering(plans)

    result.plans = plans
    result
  end

  private

  def base_scope
    Plan.parents.where(organization:).where(pending_deletion: false).ransack(search_params)
  end

  def search_params
    return if search_term.blank?

    {
      m: 'or',
      name_cont: search_term,
      code_cont: search_term
    }
  end
end
