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

  enum :status, STATUSES
  enum :frequency, FREQUENCIES

  monetize :amount_cents, disable_validation: true, allow_nil: true

  validates :amount_cents, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validates :amount_currency, inclusion: {in: currency_list}, allow_nil: true

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end
end

# == Schema Information
#
# Table name: applied_coupons
#
#  id                           :uuid             not null, primary key
#  amount_cents                 :bigint
#  amount_currency              :string
#  frequency                    :integer          default("once"), not null
#  frequency_duration           :integer
#  frequency_duration_remaining :integer
#  percentage_rate              :decimal(10, 5)
#  status                       :integer          default("active"), not null
#  terminated_at                :datetime
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  coupon_id                    :uuid             not null
#  customer_id                  :uuid             not null
#
# Indexes
#
#  index_applied_coupons_on_coupon_id    (coupon_id)
#  index_applied_coupons_on_customer_id  (customer_id)
#
