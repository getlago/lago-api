# frozen_string_literal: true

class Coupon < ApplicationRecord
  include Currencies

  belongs_to :organization

  has_many :applied_coupons
  has_many :customers, through: :applied_coupons

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

  scope :order_by_status_and_expiration, lambda {
    order(
      Arel.sql(
        [
          'coupons.status ASC',
          'coupons.expiration ASC',
          'coupons.created_at + make_interval(days => COALESCE(coupons.expiration_duration, 0)) ASC',
        ].join(', '),
      ),
    )
  }

  def attached_to_customers?
    applied_coupons.exists?
  end

  def deletable?
    !attached_to_customers?
  end

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  def expiration_date
    return unless expiration_duration

    created_at.to_date + object.expiration_duration.days
  end
end
