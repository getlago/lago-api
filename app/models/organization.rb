# frozen_string_literal: true

class Organization < ApplicationRecord
  has_many :memberships
  has_many :users, through: :memberships
  has_many :billable_metrics
  has_many :plans
  has_many :customers
  has_many :subscriptions, through: :customers
  has_many :invoices, through: :customers
  has_many :events
  has_many :coupons
  has_many :add_ons
  has_many :payment_providers

  has_one :stripe_payment_provider, class_name: 'PaymentProviders::StripeProvider'

  before_create :generate_api_key

  validates :name, presence: true
  validates :webhook_url, url: true, allow_nil: true
  validates :vat_rate, numericality: { less_than_or_equal_to: 100, greater_than_or_equal_to: 0 }

  private

  def generate_api_key
    api_key = SecureRandom.uuid
    orga = Organization.find_by(api_key: api_key)

    return generate_api_key if orga.present?

    self.api_key = SecureRandom.uuid
  end
end
