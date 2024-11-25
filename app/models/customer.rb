# frozen_string_literal: true

class Customer < ApplicationRecord
  include PaperTrailTraceable
  include Sequenced
  include Currencies
  include CustomerTimezone
  include OrganizationTimezone
  include Discard::Model
  self.discard_column = :deleted_at

  FINALIZE_ZERO_AMOUNT_INVOICE_OPTIONS = [
    :inherit,
    :skip,
    :finalize
  ].freeze

  CUSTOMER_TYPES = {
    company: 'company',
    individual: 'individual'
  }.freeze

  attribute :finalize_zero_amount_invoice, :integer
  enum finalize_zero_amount_invoice: FINALIZE_ZERO_AMOUNT_INVOICE_OPTIONS, _prefix: :finalize_zero_amount_invoice
  attribute :customer_type, :string
  enum customer_type: CUSTOMER_TYPES, _prefix: :customer_type

  before_save :ensure_slug

  belongs_to :organization
  belongs_to :applied_dunning_campaign, optional: true, class_name: "DunningCampaign"

  has_many :subscriptions
  has_many :events
  has_many :invoices
  has_many :applied_coupons
  has_many :metadata, class_name: 'Metadata::CustomerMetadata', dependent: :destroy
  has_many :coupons, through: :applied_coupons
  has_many :credit_notes
  has_many :applied_add_ons
  has_many :add_ons, through: :applied_add_ons
  has_many :daily_usages
  has_many :wallets
  has_many :wallet_transactions, through: :wallets
  has_many :payment_provider_customers,
    class_name: 'PaymentProviderCustomers::BaseCustomer',
    dependent: :destroy
  has_many :payment_requests, dependent: :destroy
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
  has_one :hubspot_customer, class_name: 'IntegrationCustomers::HubspotCustomer'
  has_one :salesforce_customer, class_name: 'IntegrationCustomers::SalesforceCustomer'

  PAYMENT_PROVIDERS = %w[stripe gocardless adyen].freeze

  default_scope -> { kept }
  sequenced scope: ->(customer) { customer.organization.customers.with_discarded },
    lock_key: ->(customer) { customer.organization_id }

  scope :falling_back_to_default_dunning_campaign, -> {
    where(applied_dunning_campaign_id: nil, exclude_from_dunning_campaign: false)
  }
  scope :with_dunning_campaign_not_completed, -> { where(dunning_campaign_completed: false) }

  validates :country, :shipping_country, country_code: true, allow_nil: true
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
  validates :email, email: true, if: :email?

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name firstname lastname legal_name external_id email]
  end

  def display_name(prefer_legal_name: true)
    names = prefer_legal_name ? [legal_name.presence || name.presence] : [name.presence]

    if firstname.present? || lastname.present?
      names << '-' if names.compact.present?
      names << firstname
      names << lastname
    end
    names.compact.join(' ')
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

  def same_billing_and_shipping_address?
    return true if shipping_address.values.all?(&:blank?)

    address_line1 == shipping_address_line1 &&
      address_line2 == shipping_address_line2 &&
      city == shipping_city &&
      zipcode == shipping_zipcode &&
      state == shipping_state &&
      country == shipping_country
  end

  def empty_billing_and_shipping_address?
    shipping_address.values.all?(&:blank?) &&
      address_line1.blank? &&
      address_line2.blank? &&
      city.blank? &&
      zipcode.blank? &&
      state.blank? &&
      country.blank?
  end

  def overdue_balance_cents
    invoices.payment_overdue.where(currency:).sum(:total_amount_cents)
  end

  private

  def ensure_slug
    return if slug.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.slug = "#{organization.document_number_prefix}-#{formatted_sequential_id}"
  end
end

# == Schema Information
#
# Table name: customers
#
#  id                               :uuid             not null, primary key
#  address_line1                    :string
#  address_line2                    :string
#  city                             :string
#  country                          :string
#  currency                         :string
#  customer_type                    :enum
#  deleted_at                       :datetime
#  document_locale                  :string
#  dunning_campaign_completed       :boolean          default(FALSE)
#  email                            :string
#  exclude_from_dunning_campaign    :boolean          default(FALSE), not null
#  finalize_zero_amount_invoice     :integer          default("inherit"), not null
#  firstname                        :string
#  invoice_grace_period             :integer
#  last_dunning_campaign_attempt    :integer          default(0), not null
#  last_dunning_campaign_attempt_at :datetime
#  lastname                         :string
#  legal_name                       :string
#  legal_number                     :string
#  logo_url                         :string
#  name                             :string
#  net_payment_term                 :integer
#  payment_provider                 :string
#  payment_provider_code            :string
#  phone                            :string
#  shipping_address_line1           :string
#  shipping_address_line2           :string
#  shipping_city                    :string
#  shipping_country                 :string
#  shipping_state                   :string
#  shipping_zipcode                 :string
#  slug                             :string
#  state                            :string
#  tax_identification_number        :string
#  timezone                         :string
#  url                              :string
#  vat_rate                         :float
#  zipcode                          :string
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  applied_dunning_campaign_id      :uuid
#  external_id                      :string           not null
#  external_salesforce_id           :string
#  organization_id                  :uuid             not null
#  sequential_id                    :bigint
#
# Indexes
#
#  index_customers_on_applied_dunning_campaign_id      (applied_dunning_campaign_id)
#  index_customers_on_deleted_at                       (deleted_at)
#  index_customers_on_external_id_and_organization_id  (external_id,organization_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_customers_on_organization_id                  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (applied_dunning_campaign_id => dunning_campaigns.id)
#  fk_rails_...  (organization_id => organizations.id)
#
