# frozen_string_literal: true

class Customer < ApplicationRecord
  belongs_to :organization

  has_many :subscriptions
  has_many :events
  has_many :invoices, through: :subscriptions
  has_many :applied_coupons
  has_many :coupons, through: :applied_coupons
  has_many :applied_add_ons
  has_many :add_ons, through: :applied_add_ons
  has_many :payment_provider_customers

  has_one :stripe_customer, class_name: 'PaymentProviderCustomers::StripeCustomer'

  PAYMENT_PROVIDERS = %w[stripe].freeze

  validates :customer_id, presence: true, uniqueness: { scope: :organization_id }
  validates :country, country_code: true, if: :country?
  validates :vat_rate, numericality: { less_than_or_equal_to: 100, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_provider, inclusion: { in: PAYMENT_PROVIDERS }, allow_nil: true

  def attached_to_subscriptions?
    subscriptions.exists?
  end

  def deletable?
    !attached_to_subscriptions?
  end

  def active_subscription
    subscriptions.active.order(started_at: :desc).first
  end

  def applicable_vat_rate
    return vat_rate if vat_rate.present?

    organization.vat_rate || 0
  end
end
