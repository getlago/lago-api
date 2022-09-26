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

  FREQUENCIES = [
    :once,
    :recurring,
  ].freeze

  enum status: STATUSES
  enum frequency: FREQUENCIES

  monetize :amount_cents

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :amount_currency, inclusion: { in: currency_list }

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end
end
