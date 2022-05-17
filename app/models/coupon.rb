# frozen_string_literal: true

class Coupon < ApplicationRecord
  include Currencies

  belongs_to :organization

  COUPON_TYPES = %i[
    fixed_amount
    free_days
  ].freeze

  enum coupon_type: COUPON_TYPES

  monetize :amount_cents, allow_nil: true

  validates :name, presence: true
  validates :code, uniqueness: { scope: :organization_id, allow_nil: true }

  validates :amount_cents, numericality: { greater_than: 0 }, if: :fixed_amount?
  validates :amount_currency, inclusion: { in: currency_list }, if: :fixed_amount?

  validates :day_count, numericality: { greater_than: 0 }, if: :free_days?

  def can_be_deleted
    # TODO: implement logic
    true
  end
end
