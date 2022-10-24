# frozen_string_literal: true

class Organization < ApplicationRecord
  has_many :memberships
  has_many :users, through: :memberships
  has_many :billable_metrics
  has_many :plans
  has_many :customers
  has_many :subscriptions, through: :customers
  has_many :invoices, through: :customers
  has_many :credit_notes, through: :customers
  has_many :events
  has_many :coupons
  has_many :add_ons
  has_many :invites
  has_many :payment_providers
  has_many :wallets, through: :customers
  has_many :wallet_transactions, through: :wallets

  has_one :stripe_payment_provider, class_name: 'PaymentProviders::StripeProvider'
  has_one :gocardless_payment_provider, class_name: 'PaymentProviders::GocardlessProvider'

  has_one_attached :logo

  before_create :generate_api_key

  validates :name, presence: true
  validates :webhook_url, url: true, allow_nil: true
  validates :vat_rate, numericality: { less_than_or_equal_to: 100, greater_than_or_equal_to: 0 }
  validates :country, country_code: true, unless: -> { country.nil? }
  validates :invoice_footer, length: { maximum: 600 }
  validates :email, email: true, if: :email?
  validates :logo,
            image: { authorized_content_type: %w[image/png image/jpg image/jpeg], max_size: 800.kilobytes },
            if: :logo?

  def logo_url
    return if logo.blank?

    Rails.application.routes.url_helpers.rails_blob_url(logo, host: ENV['LAGO_API_URL'])
  end

  def base64_logo
    return if logo.blank?

    logo.blob.open do |tempfile|
      data = tempfile.read
      Base64.encode64(data)
    end
  end

  private

  def generate_api_key
    api_key = SecureRandom.uuid
    orga = Organization.find_by(api_key: api_key)

    return generate_api_key if orga.present?

    self.api_key = SecureRandom.uuid
  end
end
