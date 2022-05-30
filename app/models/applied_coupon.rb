# frozen_string_literal: true

class AppliedCoupon < ApplicationRecord
  include Currencies

  belongs_to :coupon
  belongs_to :customer

  has_many :credits

  STATUSES = [
    :active,
    :terminated,
  ].freeze

  enum status: STATUSES

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end
end
