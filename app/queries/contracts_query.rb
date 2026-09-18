# frozen_string_literal: true

class ContractsQuery < BaseQuery
  Result = BaseResult[:contracts]
  Filters = BaseFilters[
    :external_customer_id,
    :plan_code,
    :external_id,
    :status,
    :billing_entity_ids,
    :has_rate_overrides
  ]

  def call
    contracts = base_scope
    contracts = paginate(contracts)
    contracts = apply_consistent_ordering(contracts)

    contracts = with_external_customer(contracts) if filters.external_customer_id.present?
    contracts = with_plan_code(contracts) if filters.plan_code.present?
    contracts = with_external_id(contracts) if filters.external_id.present?
    contracts = with_status(contracts) if filters.status.present?
    contracts = with_billing_entity_ids(contracts) if filters.billing_entity_ids.present?
    contracts = with_rate_overrides(contracts) unless has_rate_overrides_filter.nil?

    result.contracts = contracts
    result
  end

  private

  def base_scope
    scope = Contract.where(organization:)
    scope = scope.where(id: matching_ids_by_search) if search_term.present? && filters.external_id.blank?
    scope
  end

  # Free-text search is expressed as a UNION of single-table branches (rather
  # than a cross-table ransack OR) so each branch can use its own trigram
  # index instead of forcing a sequential scan — the same shape SubscriptionsQuery
  # uses. A contract has no name of its own often, so the plan and customer
  # branches carry most matches.
  def matching_ids_by_search
    escaped_term = "%#{Contract.sanitize_sql_like(search_term)}%"
    search_base = Contract.where(organization:)

    branches = [
      search_base.where("contracts.name ILIKE ?", escaped_term).select(:id),
      search_base.where("contracts.external_id ILIKE ?", escaped_term).select(:id),
      search_base.where(catalog_plan_id: matching_plan_ids).select(:id)
    ]

    branches << search_base.where(id: search_term).select(:id) if search_term.match?(BaseQuery::UUID_REGEX)
    branches << search_base.where(customer_id: matching_customer_ids).select(:id) if search_customers?

    union_sql = branches.map(&:to_sql).join(" UNION ")
    Contract.unscoped.from("(#{union_sql}) AS contracts").select(:id)
  end

  def matching_plan_ids
    escaped_term = "%#{CatalogPlan.sanitize_sql_like(search_term)}%"

    CatalogPlan.where(organization:)
      .where("catalog_plans.name ILIKE :term OR catalog_plans.code ILIKE :term", term: escaped_term)
      .select(:id)
  end

  def matching_customer_ids
    escaped_term = "%#{Customer.sanitize_sql_like(search_term)}%"

    Customer.where(organization:)
      .where(
        "customers.name ILIKE :term OR customers.firstname ILIKE :term " \
        "OR customers.lastname ILIKE :term OR customers.external_id ILIKE :term " \
        "OR customers.email ILIKE :term",
        term: escaped_term
      )
      .select(:id)
  end

  def search_customers?
    filters.external_customer_id.blank?
  end

  def with_external_customer(scope)
    scope.where(customer_id: organization.customers.where(external_id: filters.external_customer_id).select(:id))
  end

  def with_plan_code(scope)
    scope.where(catalog_plan_id: organization.catalog_plans.where(code: filters.plan_code).select(:id))
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

  # A contract's effective billing entity is its own override, falling back to
  # the customer's — so a filter on a billing entity must match either side,
  # the same rule SubscriptionsQuery applies.
  def with_billing_entity_ids(scope)
    scope.joins(:customer).where(
      "contracts.billing_entity_id IN (?) OR " \
      "(contracts.billing_entity_id IS NULL AND customers.billing_entity_id IN (?))",
      filters.billing_entity_ids,
      filters.billing_entity_ids
    )
  end

  # A contract has rate overrides when a current or scheduled card carries an
  # override on one of its own phases. Own phases only: a plan-level override
  # is the plan's shared pricing, not a per-contract one, so an inherited phase
  # does not count. Live cards only: an ended card is history, dropped from the
  # applied-card count, so an override on it must not flip the flag. The id
  # subquery lets the boolean invert without a row-duplicating join.
  def with_rate_overrides(scope)
    overriding_ids = ContractRateCard.current_and_scheduled
      .where(organization:)
      .joins(:rate_phases)
      .where.not(rate_phases: {rate_override_id: nil})
      .select(:contract_id)

    if ActiveModel::Type::Boolean.new.cast(has_rate_overrides_filter)
      scope.where(id: overriding_ids)
    else
      scope.where.not(id: overriding_ids)
    end
  end

  def has_rate_overrides_filter
    filters.has_rate_overrides
  end
end
