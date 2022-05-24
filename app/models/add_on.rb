# frozen_string_literal: true

class AddOn < ApplicationRecord
  include Currencies

  belongs_to :organization

  monetize :amount_cents

  validates :name, presence: true
  validates :code, uniqueness: { scope: :organization_id, allow_nil: false }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }
end
