# frozen_string_literal: true

class Organization < ApplicationRecord
  include PaperTrailTraceable
  include OrganizationTimezone
  include Currencies

  EMAIL_SETTINGS = [
    "invoice.finalized",
    "credit_note.created",
    "payment_receipt.created"
  ].freeze

  MULTI_ENTITIES_MAX = {
    default: 1,
    pro: 2,
    enterprise: Float::INFINITY
  }.freeze

  has_many :api_keys
  has_many :billing_entities, -> { active }
  has_many :all_billing_entities, class_name: "BillingEntity"
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
  has_many :daily_usages
  has_many :invites
  has_many :integrations, class_name: "Integrations::BaseIntegration"
  has_many :payment_providers, class_name: "PaymentProviders::BaseProvider"
  has_many :payment_requests
  has_many :taxes
  has_many :wallets, through: :customers
  has_many :wallet_transactions, through: :wallets
  has_many :webhook_endpoints
  has_many :webhooks, through: :webhook_endpoints
  has_many :cached_aggregations
  has_many :data_exports
  has_many :error_details
  has_many :dunning_campaigns

  has_many :subscription_activities, class_name: "UsageMonitoring::SubscriptionActivity"

  has_many :stripe_payment_providers, class_name: "PaymentProviders::StripeProvider"
  has_many :gocardless_payment_providers, class_name: "PaymentProviders::GocardlessProvider"
  has_many :cashfree_payment_providers, class_name: "PaymentProviders::CashfreeProvider"
  has_many :adyen_payment_providers, class_name: "PaymentProviders::AdyenProvider"

  has_many :hubspot_integrations, class_name: "Integrations::HubspotIntegration"
  has_many :netsuite_integrations, class_name: "Integrations::NetsuiteIntegration"
  has_many :xero_integrations, class_name: "Integrations::XeroIntegration"
  has_one :salesforce_integration, class_name: "Integrations::SalesforceIntegration"

  has_one :applied_dunning_campaign, -> { where(applied_to_organization: true) }, class_name: "DunningCampaign"
  has_one :default_billing_entity, -> { active.order(created_at: :asc) }, class_name: "BillingEntity"

  has_many :invoice_custom_sections
  has_many :invoice_custom_section_selections
  has_many :manual_invoice_custom_sections, -> { where(section_type: :manual) }, class_name: "InvoiceCustomSection"
  has_many :system_generated_invoice_custom_sections, -> { where(section_type: :system_generated) }, class_name: "InvoiceCustomSection"
  has_many :selected_invoice_custom_sections, through: :invoice_custom_section_selections, source: :invoice_custom_section

  has_one_attached :logo

  DOCUMENT_NUMBERINGS = [
    :per_customer,
    :per_organization
  ].freeze

  INTEGRATIONS = %w[
    beta_payment_authorization
    netsuite
    okta
    anrok
    avalara
    xero
    progressive_billing
    lifetime_usage
    hubspot
    auto_dunning
    revenue_analytics
    salesforce
    api_permissions
    revenue_share
    zero_amount_fees
    remove_branding_watermark
    manual_payments
    from_email
    issue_receipts
    preview
    multi_entities_pro
    multi_entities_enterprise
    analytics_dashboards
  ].freeze
  PREMIUM_INTEGRATIONS = INTEGRATIONS - %w[anrok]
  INTEGRATIONS_TRACKING_ACTIVITY = %w[lifetime_usage progressive_billing].freeze

  enum :document_numbering, DOCUMENT_NUMBERINGS

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
  validates :hmac_key, uniqueness: true
  validates :hmac_key, presence: true, on: :update

  validate :validate_email_settings

  before_create :set_hmac_key
  after_create :generate_document_number_prefix

  scope :with_any_premium_integrations, ->(names) { where("premium_integrations && ARRAY[?]::varchar[]", Array.wrap(names)) }
  scope :with_activity_tracking, -> { with_any_premium_integrations(INTEGRATIONS_TRACKING_ACTIVITY) }

  PREMIUM_INTEGRATIONS.each do |premium_integration|
    scope "with_#{premium_integration}_support", -> { where("? = ANY(premium_integrations)", premium_integration) }

    define_method("#{premium_integration}_enabled?") do
      License.premium? && premium_integrations.include?(premium_integration)
    end
  end

  def tracks_subscription_activity?
    return false unless License.premium?

    (INTEGRATIONS_TRACKING_ACTIVITY & premium_integrations).any?
  end

  def admins
    users.joins(:memberships).merge!(memberships.admin)
  end

  def logo_url
    return if logo.blank?

    Rails.application.routes.url_helpers.rails_blob_url(logo, host: ENV["LAGO_API_URL"])
  end

  def base64_logo
    return if logo.blank?

    logo.blob.open do |tempfile|
      data = tempfile.read
      Base64.encode64(data)
    end
  end

  def eu_vat_eligible?
    country && LagoEuVat::Rate.country_codes.include?(country)
  end

  def payment_provider(provider)
    case provider
    when "stripe"
      stripe_payment_provider
    when "gocardless"
      gocardless_payment_provider
    when "cashfree"
      cashfree_payment_provider
    when "adyen"
      adyen_payment_provider
    end
  end

  def document_number_prefix=(value)
    super(value&.upcase)
  end

  def reset_customers_last_dunning_campaign_attempt
    customers
      .falling_back_to_default_dunning_campaign
      .update_all( # rubocop:disable Rails/SkipsModelValidations
        last_dunning_campaign_attempt: 0,
        last_dunning_campaign_attempt_at: nil
      )
  end

  def from_email_address
    return email if from_email_enabled?

    ENV["LAGO_FROM_EMAIL"]
  end

  def can_create_billing_entity?
    remaining_billing_entities > 0
  end

  def failed_tax_invoices_count
    invoices.where(status: :failed).joins(:error_details).where(error_details: {error_code: "tax_error"}).count
  end

  private

  # NOTE: After creating an organization, default document_number_prefix needs to be generated.
  # Example of expected format is ORG-4321
  def generate_document_number_prefix
    update!(document_number_prefix: "#{name.first(3).upcase}-#{id.last(4).upcase}")
  end

  def validate_email_settings
    return if email_settings.all? { |v| EMAIL_SETTINGS.include?(v) }

    errors.add(:email_settings, :unsupported_value)
  end

  def set_hmac_key
    loop do
      self.hmac_key = SecureRandom.uuid
      break unless self.class.exists?(hmac_key:)
    end
  end

  def remaining_billing_entities
    return MULTI_ENTITIES_MAX[:enterprise] if multi_entities_enterprise_enabled?
    return MULTI_ENTITIES_MAX[:pro] - billing_entities.active.count if multi_entities_pro_enabled?

    MULTI_ENTITIES_MAX[:default] - billing_entities.active.count
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
#  clickhouse_events_store      :boolean          default(FALSE), not null
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
#  hmac_key                     :string           not null
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
#  index_organizations_on_api_key   (api_key) UNIQUE
#  index_organizations_on_hmac_key  (hmac_key) UNIQUE
#
