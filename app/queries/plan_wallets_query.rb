# frozen_string_literal: true

class PlanWalletsQuery < BaseQuery
  Result = BaseResult[:plan_wallets]
  Filters = BaseFilters[:plan_id, :created_at_from, :created_at_to]

  def call
    plan_wallets = PlanWallet.where(organization:)
    plan_wallets = plan_wallets.where(catalog_plan_id: filters.plan_id) if filters.plan_id.present?
    plan_wallets = with_date_range(plan_wallets, :created_at)
    plan_wallets = apply_consistent_ordering(plan_wallets)

    result.plan_wallets = paginate(plan_wallets)
    result
  rescue BaseService::FailedResult
    result
  end
end
