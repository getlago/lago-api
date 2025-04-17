# frozen_string_literal: true

class WalletsQuery < BaseQuery
  Result = BaseResult[:wallets]
  Filters = BaseFilters[:external_customer_id]

  def call
    validate_filters
    return result if result.error.present?

    wallets = base_scope
    wallets = paginate(wallets)
    wallets = apply_consistent_ordering(wallets)

    wallets = with_external_customer_id(wallets) if filters.external_customer_id

    result.wallets = wallets
    result
  end

  private

  def base_scope
    organization.wallets
  end

  def with_external_customer_id(scope)
    scope.joins(:customer).where(customers: {external_id: filters.external_customer_id})
  end

  def validate_filters
    if filters.to_h.key? :external_customer_id
      result.not_found_failure!(resource: "customer") unless customer_exists?
    end
  end

  def customer_exists?
    organization.customers.exists?(external_id: filters.external_customer_id)
  end
end
