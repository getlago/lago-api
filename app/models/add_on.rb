# frozen_string_literal: true

class AddOn < ApplicationRecord
  include PaperTrailTraceable
  include Currencies
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  has_many :applied_add_ons
  has_many :customers, through: :applied_add_ons
  has_many :fees

  monetize :amount_cents

  validates :name, presence: true
  validates :code,
            uniqueness: { conditions: -> { where(deleted_at: nil) }, scope: :organization_id }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }

  default_scope -> { kept }
end
