# frozen_string_literal: true

class AddOn < ApplicationRecord
  include Currencies

  belongs_to :organization

  has_many :applied_add_ons
  has_many :customers, through: :applied_add_ons
  has_many :fees

  monetize :amount_cents

  validates :name, presence: true
  validates :code, uniqueness: { scope: :organization_id, allow_nil: false }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }

  def attached_to_customers?
    applied_add_ons.exists?
  end

  def deletable?
    !attached_to_customers?
  end
end
