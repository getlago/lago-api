# frozen_string_literal: true

class TaxRate < ApplicationRecord
  include PaperTrailTraceable

  has_many :customers_tax_rates
  has_many :customers, through: :customers_tax_rates

  belongs_to :organization

  validates :name, :value, presence: true
  validates :code, presence: true, uniqueness: { scope: :organization_id }
end
