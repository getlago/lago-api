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

  def credits_sum_for_invoice_subscription(invoice_subscription, invoice)
    credits.active.where(invoice_id: invoice_ids_for_invoice_subscription(invoice_subscription, invoice))
      .joins(:invoice).where.not(invoices: {status: :voided}).sum(&:amount_cents)
  end

  def credits_applied_in_billing_period_present?(invoice)
    invoice.invoice_subscriptions.any? do |invoice_subscription|
      credits_sum_for_invoice_subscription(invoice_subscription, invoice).positive?
    end
  end

  # coupon defines the amount that can be deducted during a billing_period. So if a coupon lasts n billing periods with m discount,
  # during each billing period the maximum discount is m
  def remaining_amount_for_this_subscription_billing_period(invoice:)
    @remaining_amount_for_this_subscription_billing_period ||= {}
    cached = @remaining_amount_for_this_subscription_billing_period[invoice.id]
    return cached unless cached.nil?

    used_amount = invoice.invoice_subscriptions.map do |invoice_subscription|
      credits_sum_for_invoice_subscription(invoice_subscription, invoice)
    end.sum

    remaining_amount = amount_cents - used_amount
    @remaining_amount_for_this_subscription_billing_period[invoice.id] = remaining_amount.negative? ? 0 : remaining_amount
  end

  private

  # Returns invoice ids whose fees for this invoice_subscription's subscription fall within
  # the billing period boundaries. Boundaries are read from a fee on the invoice rather than
  # from the invoice_subscription itself, because pay-in-advance fees carry their own
  # boundaries that may differ from the invoice_subscription record.
  def invoice_ids_for_invoice_subscription(invoice_subscription, invoice)
    boundaries = invoice.fees.where(subscription_id: invoice_subscription.subscription_id).first&.properties ||
      {"charges_from_datetime" => invoice_subscription.charges_from_datetime,
       "charges_to_datetime" => invoice_subscription.charges_to_datetime}

    Fee.where(organization_id: invoice.organization_id,
      billing_entity_id: invoice.billing_entity_id,
      subscription_id: invoice_subscription.subscription_id)
      .where("(properties->>'charges_from_datetime')::timestamptz >= ?::timestamptz", boundaries["charges_from_datetime"])
      .where("(properties->>'charges_to_datetime')::timestamptz <= ?::timestamptz", boundaries["charges_to_datetime"])
      .distinct
      .pluck(:invoice_id)
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
