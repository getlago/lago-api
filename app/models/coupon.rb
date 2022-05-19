# frozen_string_literal: true

class Coupon < ApplicationRecord
  include Currencies

  belongs_to :organization

  STATUSES = [
    :active,
    :terminated,
  ].freeze

  EXPIRATION_TYPES = [
    :no_expiration,
    :time_limit,
  ].freeze

  enum status: STATUSES
  enum expiration: EXPIRATION_TYPES

  monetize :amount_cents

  validates :name, presence: true
  validates :code, uniqueness: { scope: :organization_id, allow_nil: true }

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }

  validates :expiration_duration, numericality: { greater_than: 0 }, if: :time_limit?

  def can_be_deleted
    # TODO: implement logic
    true
  end
end
