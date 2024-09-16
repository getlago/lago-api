# frozen_string_literal: true

class Organization < ApplicationRecord
  include PaperTrailTraceable
  include OrganizationTimezone
  include Currencies

  EMAIL_SETTINGS = [
    'invoice.finalized',
    'credit_note.created'
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
  has_many :integrations, class_name: 'Integrations::BaseIntegration'
  has_many :payment_providers, class_name: 'PaymentProviders::BaseProvider'
  has_many :payment_requests
  has_many :taxes
  has_many :wallets, through: :customers
  has_many :wallet_transactions, through: :wallets
  has_many :webhook_endpoints
  has_many :webhooks, through: :webhook_endpoints
  has_many :cached_aggregations
  has_many :data_exports
  has_many :error_details

  has_many :stripe_payment_providers, class_name: 'PaymentProviders::StripeProvider'
  has_many :gocardless_payment_providers, class_name: 'PaymentProviders::GocardlessProvider'
  has_many :adyen_payment_providers, class_name: 'PaymentProviders::AdyenProvider'

  has_many :hubspot_integrations, class_name: 'Integrations::HubspotIntegration'
  has_many :netsuite_integrations, class_name: 'Integrations::NetsuiteIntegration'
  has_many :xero_integrations, class_name: 'Integrations::XeroIntegration'

  has_one_attached :logo

  DOCUMENT_NUMBERINGS = [
    :per_customer,
    :per_organization
  ].freeze

  INTEGRATIONS = %w[netsuite okta anrok xero progressive_billing dunning hubspot].freeze
  PREMIUM_INTEGRATIONS = INTEGRATIONS - %w[anrok]

  enum document_numbering: DOCUMENT_NUMBERINGS

  before_create :generate_api_key

  validates :country, country_code: true, unless: -> { country.nil? }
  validates :default_currency, inclusion: {in: currency_list}
  validates :document_locale, language_code: true
  validates :email, email: true, if: :email?
  validates :invoice_footer, length: {maximum: 600}
  validates :document_number_prefix, length: {minimum: 1, maximum: 10}, on: :update
  validates :invoice_grace_period, numericality: {greater_than_or_equal_to: 0}
  validates :net_payment_term, numericality: {greater_than_or_equal_to: 0}
  validates :logo,
    image: {authorized_content_type: %w[image/png image/jpg image/jpeg], max_size: 800.kilobytes},
    if: :logo?
  validates :name, presence: true
  validates :timezone, timezone: true
  validates :webhook_url, url: true, allow_nil: true
  validates :finalize_zero_amount_invoice, inclusion: {in: [true, false]}

  validate :validate_email_settings

  after_create :generate_document_number_prefix

  PREMIUM_INTEGRATIONS.each do |premium_integration|
    scope "with_#{premium_integration}_support", -> { where("? = ANY(premium_integrations)", premium_integration) }
  end

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

  def eu_vat_eligible?
    country && LagoEuVat::Rate.new.countries_code.include?(country)
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

  def document_number_prefix=(value)
    super(value&.upcase)
  end

  private

  def generate_api_key
    api_key = SecureRandom.uuid
    orga = Organization.find_by(api_key:)

    return generate_api_key if orga.present?

    self.api_key = SecureRandom.uuid
  end

  # NOTE: After creating an organization, default document_number_prefix needs to be generated.
  # Example of expected format is ORG-4321
  def generate_document_number_prefix
    update!(document_number_prefix: "#{name.first(3).upcase}-#{id.last(4).upcase}")
  end

  def validate_email_settings
    return if email_settings.all? { |v| EMAIL_SETTINGS.include?(v) }

    errors.add(:email_settings, :unsupported_value)
  end
end

# == Schema Information
#
# Table name: organizations
#
#  id                           :uuid             not null, primary key
#  address_line1                :string
#  address_line2                :string
#  api_key                      :string
#  city                         :string
#  clickhouse_aggregation       :boolean          default(FALSE), not null
#  country                      :string
#  custom_aggregation           :boolean          default(FALSE)
#  default_currency             :string           default("USD"), not null
#  document_locale              :string           default("en"), not null
#  document_number_prefix       :string
#  document_numbering           :integer          default("per_customer"), not null
#  email                        :string
#  email_settings               :string           default([]), not null, is an Array
#  eu_tax_management            :boolean          default(FALSE)
#  finalize_zero_amount_invoice :boolean          default(TRUE), not null
#  invoice_footer               :text
#  invoice_grace_period         :integer          default(0), not null
#  legal_name                   :string
#  legal_number                 :string
#  logo                         :string
#  name                         :string           not null
#  net_payment_term             :integer          default(0), not null
#  premium_integrations         :string           default([]), not null, is an Array
#  state                        :string
#  tax_identification_number    :string
#  timezone                     :string           default("UTC"), not null
#  vat_rate                     :float            default(0.0), not null
#  webhook_url                  :string
#  zipcode                      :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_organizations_on_api_key  (api_key) UNIQUE
#
