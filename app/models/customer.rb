# frozen_string_literal: true

class Customer < ApplicationRecord
  include PaperTrailTraceable
  include Sequenced
  include Currencies
  include CustomerTimezone
  include OrganizationTimezone
  include Discard::Model
  self.discard_column = :deleted_at

  before_save :ensure_slug

  belongs_to :organization

  has_many :subscriptions
  has_many :events
  has_many :invoices
  has_many :applied_coupons
  has_many :metadata, class_name: 'Metadata::CustomerMetadata', dependent: :destroy
  has_many :coupons, through: :applied_coupons
  has_many :credit_notes
  has_many :applied_add_ons
  has_many :add_ons, through: :applied_add_ons
  has_many :wallets
  has_many :wallet_transactions, through: :wallets
  has_many :payment_provider_customers,
    class_name: 'PaymentProviderCustomers::BaseCustomer',
    dependent: :destroy
  has_many :quantified_events
  has_many :integration_customers,
    class_name: 'IntegrationCustomers::BaseCustomer',
    dependent: :destroy

  has_many :applied_taxes, class_name: 'Customer::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  has_one :stripe_customer, class_name: 'PaymentProviderCustomers::StripeCustomer'
  has_one :gocardless_customer, class_name: 'PaymentProviderCustomers::GocardlessCustomer'
  has_one :adyen_customer, class_name: 'PaymentProviderCustomers::AdyenCustomer'
  has_one :netsuite_customer, class_name: 'IntegrationCustomers::NetsuiteCustomer'
  has_one :anrok_customer, class_name: 'IntegrationCustomers::AnrokCustomer'
  has_one :xero_customer, class_name: 'IntegrationCustomers::XeroCustomer'

  PAYMENT_PROVIDERS = %w[stripe gocardless adyen].freeze

  default_scope -> { kept }
  sequenced scope: ->(customer) { customer.organization.customers.with_discarded },
    lock_key: ->(customer) { customer.organization_id }

  validates :country, country_code: true, unless: -> { country.nil? }
  validates :document_locale, language_code: true, unless: -> { document_locale.nil? }
  validates :currency, inclusion: {in: currency_list}, allow_nil: true
  validates :external_id,
    presence: true,
    uniqueness: {conditions: -> { where(deleted_at: nil) }, scope: :organization_id},
    unless: :deleted_at
  validates :invoice_grace_period, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validates :net_payment_term, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validates :payment_provider, inclusion: {in: PAYMENT_PROVIDERS}, allow_nil: true
  validates :timezone, timezone: true, allow_nil: true

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name external_id email]
  end

  def active_subscription
    subscriptions.active.order(started_at: :desc).first
  end

  def active_subscriptions
    subscriptions.active.order(started_at: :desc)
  end

  def applicable_timezone
    return timezone if timezone.present?

    organization.timezone || 'UTC'
  end

  def applicable_invoice_grace_period
    return invoice_grace_period if invoice_grace_period.present?

    organization.invoice_grace_period
  end

  def applicable_net_payment_term
    return net_payment_term if net_payment_term.present?

    organization.net_payment_term
  end

  def editable?
    subscriptions.none? &&
      applied_add_ons.none? &&
      invoices.none? &&
      applied_coupons.where.not(amount_currency: nil).none? &&
      wallets.none?
  end

  def preferred_document_locale
    return document_locale.to_sym if document_locale?

    organization.document_locale.to_sym
  end

  def provider_customer
    case payment_provider&.to_sym
    when :stripe
      stripe_customer
    when :gocardless
      gocardless_customer
    when :adyen
      adyen_customer
    end
  end

  def shipping_address
    {
      address_line1: shipping_address_line1,
      address_line2: shipping_address_line2,
      city: shipping_city,
      zipcode: shipping_zipcode,
      state: shipping_state,
      country: shipping_country
    }
  end

  private

  def ensure_slug
    return if slug.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.slug = "#{organization.document_number_prefix}-#{formatted_sequential_id}"
  end
end
