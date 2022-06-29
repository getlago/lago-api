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

  has_one_attached :logo

  before_create :generate_api_key

  validates :name, presence: true
  validates :webhook_url, url: true, allow_nil: true
  validates :vat_rate, numericality: { less_than_or_equal_to: 100, greater_than_or_equal_to: 0 }
  validates :country, country_code: true, if: :country?
  validates :invoice_footer, length: { maximum: 600 }
  validates :email, email: true, if: :email?
  validates :logo, image: { authorized_content_type: %w[image/png image/jpg], max_size: 800.kilobytes }, if: :logo?

  def logo_url
    Rails.application.routes.url_helpers.rails_blob_url(logo, host: ENV['LAGO_API_URL'])
  end

  private

  def generate_api_key
    api_key = SecureRandom.uuid
    orga = Organization.find_by(api_key: api_key)

    return generate_api_key if orga.present?

    self.api_key = SecureRandom.uuid
  end
end
