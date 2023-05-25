# frozen_string_literal: true

class Organization < ApplicationRecord
  include PaperTrailTraceable
  include OrganizationTimezone

  EMAIL_SETTINGS = [
    'invoice.finalized',
    'credit_note.created',
  ].freeze

  has_many :memberships
  has_many :users, through: :memberships
  has_many :billable_metrics
  has_many :plans
  has_many :customers
  has_many :subscriptions, through: :customers
  has_many :invoices
  has_many :credit_notes, through: :invoices
  has_many :fees, through: :subscriptions
  has_many :events
  has_many :coupons
  has_many :applied_coupons, through: :coupons
  has_many :add_ons
  has_many :invites
  has_many :payment_providers
  has_many :taxes
  has_many :wallets, through: :customers
  has_many :wallet_transactions, through: :wallets
  has_many :webhooks

  has_one :stripe_payment_provider, class_name: 'PaymentProviders::StripeProvider'
  has_one :gocardless_payment_provider, class_name: 'PaymentProviders::GocardlessProvider'
  has_one :adyen_payment_provider, class_name: 'PaymentProviders::AdyenProvider'

  has_one_attached :logo

  before_create :generate_api_key

  validates :country, country_code: true, unless: -> { country.nil? }
  validates :document_locale, language_code: true
  validates :email, email: true, if: :email?
  validates :invoice_footer, length: { maximum: 600 }
  validates :invoice_grace_period, numericality: { greater_than_or_equal_to: 0 }
  validates :logo,
            image: { authorized_content_type: %w[image/png image/jpg image/jpeg], max_size: 800.kilobytes },
            if: :logo?
  validates :name, presence: true
  validates :timezone, timezone: true
  validates :vat_rate, numericality: { less_than_or_equal_to: 100, greater_than_or_equal_to: 0 }
  validates :webhook_url, url: true, allow_nil: true

  validate :validate_email_settings

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

  def payment_provider(provider)
    case provider
    when 'stripe'
      stripe_payment_provider
    when 'gocardless'
      gocardless_payment_provider
    when 'adyen'
      adyen_payment_provider
    end
  end

  private

  def generate_api_key
    api_key = SecureRandom.uuid
    orga = Organization.find_by(api_key:)

    return generate_api_key if orga.present?

    self.api_key = SecureRandom.uuid
  end

  def validate_email_settings
    return if email_settings.all? { |v| EMAIL_SETTINGS.include?(v) }

    errors.add(:email_settings, :unsupported_value)
  end
end
