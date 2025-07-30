# frozen_string_literal: true

class AppliedCoupon < ApplicationRecord
  include PaperTrailTraceable
  include Currencies

  belongs_to :coupon
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
    # unfortunately it's a known issue that when we create an invoice_subscription for paid_in_advance fees,
    # the boundaries are taken from the prev billing period, while fees have correct boundaries
    boundaries = invoice.fees.where(subscription_id: invoice_subscription.subscription_id).first&.properties ||
      {"charges_from_datetime" => invoice_subscription.charges_from_datetime, "charges_to_datetime" => invoice_subscription.charges_to_datetime}

    # note: fee's precise coupon amount cents also includes progressive billing
    invoice_ids = Fee.where(organization_id: invoice.organization_id,
      billing_entity_id: invoice.billing_entity_id,
      subscription_id: invoice_subscription.subscription_id)
      .where("(properties->>'charges_from_datetime')::timestamptz >= ?::timestamptz", boundaries["charges_from_datetime"])
      .where("(properties->>'charges_to_datetime')::timestamptz <= ?::timestamptz", boundaries["charges_to_datetime"])
      .pluck(:invoice_id).uniq

    credits.active.where(invoice_id: invoice_ids).joins(:invoice).where.not(invoices: {status: :voided}).sum(&:amount_cents)
  end

  def credits_applied_in_billing_period_present?(invoice)
    invoice.invoice_subscriptions.map do |invoice_subscription|
      credits_sum_for_invoice_subscription(invoice_subscription, invoice)
    end.sum > 0
  end

  def remaining_amount_for_this_subscription_billing_period(invoice:)
    @remaining_amount_for_this_subscription_billing_period ||= {}
    return @remaining_amount_for_this_subscription_billing_period[invoice.id] if @remaining_amount_for_this_subscription_billing_period[invoice.id].present?

    min_used_amount = invoice.invoice_subscriptions.map do |invoice_subscription|
      credits_sum_for_invoice_subscription(invoice_subscription, invoice)
    end.min

    remaining_amount = amount_cents - min_used_amount
    @remaining_amount_for_this_subscription_billing_period[invoice.id] = remaining_amount.negative? ? 0 : remaining_amount
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
