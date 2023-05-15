# frozen_string_literal: true

class TaxRate < ApplicationRecord
  include PaperTrailTraceable

  has_many :applied_tax_rates
  has_many :customers, through: :applied_tax_rates

  belongs_to :organization

  validates :name, :value, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }

  def customers_count
    applicable_customers.count
  end

  def applicable_customers
    return customers unless applied_by_default

    # NOTE: When applied to the organization
    #       customer list = customer wihout tax rate + customer attached to the current tax rate
    customers_without_tax_rates_query = organization.customers.left_joins(:applied_tax_rates)
      .group('customers.id')
      .having('COUNT(applied_tax_rates.id) = 0')
      .select(:id)
    organization.customers.where(id: customers_without_tax_rates_query)
      .or(organization.customers.where(id: customers.select(:id)))
  end
end
