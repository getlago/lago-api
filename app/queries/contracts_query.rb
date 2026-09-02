# frozen_string_literal: true

class ContractsQuery < BaseQuery
  Result = BaseResult[:contracts]
  Filters = BaseFilters[:external_customer_id, :plan_code, :external_id, :status]

  def call
    contracts = base_scope
    contracts = paginate(contracts)
    contracts = apply_consistent_ordering(contracts)

    contracts = with_external_customer(contracts) if filters.external_customer_id.present?
    contracts = with_plan_code(contracts) if filters.plan_code.present?
    contracts = with_external_id(contracts) if filters.external_id.present?
    contracts = with_status(contracts) if filters.status.present?

    result.contracts = contracts
    result
  end

  private

  def base_scope
    Contract.where(organization:)
  end

  def with_external_customer(scope)
    scope.where(customer_id: organization.customers.where(external_id: filters.external_customer_id).select(:id))
  end

  def with_plan_code(scope)
    scope.where(plan_id: organization.plans.where(code: filters.plan_code).select(:id))
  end

  def with_external_id(scope)
    scope.where(external_id: filters.external_id)
  end

  # The column is a PostgreSQL enum: an unknown value in the IN list would be
  # a database-level cast error, so unknown values are dropped. A filter left
  # with no valid value matches nothing rather than everything.
  def with_status(scope)
    statuses = Array(filters.status).map(&:to_s) & Contract::STATUSES.values

    scope.where(status: statuses)
  end
end
