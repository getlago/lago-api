# frozen_string_literal: true

class AppliedCoupon < ApplicationRecord
  include PaperTrailTraceable
  include Currencies

  belongs_to :coupon
  belongs_to :customer

  has_many :credits

  STATUSES = [
    :active,
    :terminated
  ].freeze

  FREQUENCIES = [
    :once,
    :recurring,
    :forever
  ].freeze

  enum status: STATUSES
  enum frequency: FREQUENCIES

  monetize :amount_cents, disable_validation: true, allow_nil: true

  validates :amount_cents, numericality: {greater_than: 0}, allow_nil: true
  validates :amount_currency, inclusion: {in: currency_list}, allow_nil: true

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end
end
