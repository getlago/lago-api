# frozen_string_literal: true

class Coupon < ApplicationRecord
  include Currencies

  belongs_to :organization

  COUPON_TYPES = %i[
    fixed_amount
    fixed_days
  ].freeze

  EXPIRATION_TYPE = %i[
    no_expiration
    user_limit
    time_limit
  ].freeze

  enum coupon_type: COUPON_TYPES
  enum expiration: EXPIRATION_TYPE

  monetize :amount_cents, allow_nil: true

  validates :name, presence: true
  validates :code, uniqueness: { scope: :organization_id, allow_nil: true }

  validates :amount_cents, numericality: { greater_than: 0 }, if: :fixed_amount?
  validates :amount_currency, inclusion: { in: currency_list }, if: :fixed_amount?
  validates :day_count, numericality: { greater_than: 0 }, if: :fixed_days?

  validates :expiration_duration, numericality: { greater_than: 0 }, if: :time_limit?
  validates :expiration_users, numericality: { greater_than: 0 }, if: :user_limit?

  def can_be_deleted
    # TODO: implement logic
    true
  end
end
