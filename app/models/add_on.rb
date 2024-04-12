# frozen_string_literal: true

class AddOn < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include IntegrationMappable
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  has_many :applied_add_ons
  has_many :customers, through: :applied_add_ons
  has_many :fees

  has_many :applied_taxes, class_name: 'AddOn::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  monetize :amount_cents

  validates :name, presence: true
  validates :code,
            uniqueness: { conditions: -> { where(deleted_at: nil) }, scope: :organization_id }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }

  default_scope -> { kept }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name code]
  end

  def invoice_name
    invoice_display_name.presence || name
  end
end
