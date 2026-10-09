# frozen_string_literal: true

class AppliedCoupon < ApplicationRecord
  include PaperTrailTraceable
  include Currencies

  belongs_to :coupon, -> { with_discarded }
  belongs_to :customer
  belongs_to :organization

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
  validates :frequency_duration, presence: true, numericality: {greater_than: 0}, if: :recurring?
  validates :frequency_duration_remaining, presence: true, numericality: {greater_than_or_equal_to: 0}, if: :recurring?

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  def remaining_amount
    return @remaining_amount if defined?(@remaining_amount)

    already_applied_amount = credits.active.sum(&:amount_cents)
    @remaining_amount = amount_cents - already_applied_amount
  end

  def remaining_amount_in_billing_period(invoice)
    [amount_cents - amount_used_in_billing_period(invoice), 0].max
  end

  def used_in_billing_period?(invoice)
    amount_used_in_billing_period(invoice).positive?
  end

  private

  # An invoice mixing service periods (e.g. next month's pay-in-advance subscription fee and last
  # month's usage) belongs to the latest one.
  def amount_used_in_billing_period(invoice)
    scopes = billing_periods(invoice).map do |subscription_id, period_from|
      credits.active.where(invoice_id: invoice_ids_in_billing_period(subscription_id, period_from))
    end

    if scopes.empty?
      0
    else
      scopes.reduce(:or).sum(:amount_cents)
    end
  end

  # Previewed invoices are not persisted, their fees only exist in memory
  def billing_periods(invoice)
    fees = invoice.persisted? ? Fee.where(invoice_id: invoice.id) : invoice.fees

    fees
      .select { |fee| Fee::SERVICE_PERIOD_FEE_TYPES.include?(fee.fee_type) }
      .group_by(&:subscription_id)
      .transform_values { |subscription_fees| subscription_fees.filter_map(&:service_period_from).max }
      .compact
  end

  def invoice_ids_in_billing_period(subscription_id, period_from)
    Fee
      .where(invoice_id: credits.active.select(:invoice_id), subscription_id:, fee_type: Fee::SERVICE_PERIOD_FEE_TYPES)
      .group(:invoice_id)
      .having("MAX(#{Fee::SERVICE_PERIOD_FROM_SQL}) = ?", period_from)
      .select(:invoice_id)
  end
end

# == Schema Information
#
# Table name: applied_coupons
# Database name: primary
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
#  organization_id              :uuid             not null
#
# Indexes
#
#  index_applied_coupons_on_coupon_id        (coupon_id)
#  index_applied_coupons_on_customer_id      (customer_id)
#  index_applied_coupons_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
