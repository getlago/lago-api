# frozen_string_literal: true

class Customer < ApplicationRecord
  include PaperTrailTraceable
  include Sequenced
  include Currencies
  include CustomerTimezone
  include OrganizationTimezone
  include BillingEntityTimezone
  include Discard::Model
  self.discard_column = :deleted_at

  FINALIZE_ZERO_AMOUNT_INVOICE_OPTIONS = [
    :inherit,
    :skip,
    :finalize
  ].freeze

  CUSTOMER_TYPES = {
    company: "company",
    individual: "individual"
  }.freeze

  ACCOUNT_TYPES = {
    customer: "customer",
    partner: "partner"
  }.freeze

  attribute :finalize_zero_amount_invoice, :integer
  enum :finalize_zero_amount_invoice, FINALIZE_ZERO_AMOUNT_INVOICE_OPTIONS, prefix: :finalize_zero_amount_invoice
  attribute :customer_type, :string
  enum :customer_type, CUSTOMER_TYPES, prefix: :customer_type, validate: {allow_nil: true}
  attribute :account_type, :string
  enum :account_type, ACCOUNT_TYPES, suffix: :account

  before_save :ensure_slug

  belongs_to :organization
  belongs_to :billing_entity, optional: true
  belongs_to :applied_dunning_campaign, optional: true, class_name: "DunningCampaign"

  has_many :subscriptions
  has_many :events
  has_many :invoices
  has_many :applied_coupons
  has_many :metadata, class_name: "Metadata::CustomerMetadata", dependent: :destroy
  has_many :coupons, through: :applied_coupons
  has_many :credit_notes
  has_many :applied_add_ons
  has_many :add_ons, through: :applied_add_ons
  has_many :daily_usages
  has_many :wallets
  has_many :wallet_transactions, through: :wallets
  has_many :payment_provider_customers,
    class_name: "PaymentProviderCustomers::BaseCustomer",
    dependent: :destroy
  has_many :payment_methods, dependent: :destroy
  has_many :payment_requests, dependent: :destroy
  has_many :quantified_events
  has_many :integration_customers,
    class_name: "IntegrationCustomers::BaseCustomer",
    dependent: :destroy

  has_many :applied_taxes, class_name: "Customer::AppliedTax", dependent: :destroy
  has_many :taxes, through: :applied_taxes

  has_many :applied_invoice_custom_sections,
    class_name: "Customer::AppliedInvoiceCustomSection",
    dependent: :destroy
  has_many :selected_invoice_custom_sections, through: :applied_invoice_custom_sections, source: :invoice_custom_section
  has_many :manual_selected_invoice_custom_sections,
    -> { where(section_type: :manual) },
    through: :applied_invoice_custom_sections,
    source: :invoice_custom_section
  has_many :system_generated_invoice_custom_sections,
    -> { where(section_type: :system_generated) },
    through: :applied_invoice_custom_sections,
    source: :invoice_custom_section

  has_many :activity_logs,
    -> { order(logged_at: :desc) },
    class_name: "Clickhouse::ActivityLog",
    foreign_key: :external_customer_id,
    primary_key: :external_id

  has_one :stripe_customer, class_name: "PaymentProviderCustomers::StripeCustomer"
  has_one :gocardless_customer, class_name: "PaymentProviderCustomers::GocardlessCustomer"
  has_one :cashfree_customer, class_name: "PaymentProviderCustomers::CashfreeCustomer"
  has_one :adyen_customer, class_name: "PaymentProviderCustomers::AdyenCustomer"
  has_one :flutterwave_customer, class_name: "PaymentProviderCustomers::FlutterwaveCustomer"
  has_one :netsuite_customer, class_name: "IntegrationCustomers::NetsuiteCustomer"
  has_one :anrok_customer, class_name: "IntegrationCustomers::AnrokCustomer"
  has_one :avalara_customer, class_name: "IntegrationCustomers::AvalaraCustomer"
  has_one :xero_customer, class_name: "IntegrationCustomers::XeroCustomer"
  has_one :hubspot_customer, class_name: "IntegrationCustomers::HubspotCustomer"
  has_one :salesforce_customer, class_name: "IntegrationCustomers::SalesforceCustomer"
  has_one :moneyhash_customer, class_name: "PaymentProviderCustomers::MoneyhashCustomer"

  PAYMENT_PROVIDERS = %w[stripe gocardless cashfree adyen flutterwave moneyhash].freeze

  default_scope -> { kept }
  sequenced scope: ->(customer) { customer.organization.customers.with_discarded },
    lock_key: ->(customer) { customer.organization_id }

  scope :falling_back_to_default_dunning_campaign, -> {
    where(applied_dunning_campaign_id: nil, exclude_from_dunning_campaign: false)
  }

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
  validates :email, email: true, if: -> { email? && will_save_change_to_email? }

  def self.ransackable_attributes(_auth_object = nil)
    %w[id name firstname lastname legal_name external_id email]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end

  def display_name(prefer_legal_name: true)
    names = prefer_legal_name ? [legal_name.presence || name.presence] : [name.presence]

    if firstname.present? || lastname.present?
      names << "-" if names.compact.present?
      names << firstname
      names << lastname
    end
    names.compact.join(" ")
  end

  def active_subscription
    subscriptions.active.order(started_at: :desc).first
  end

  def active_subscriptions
    subscriptions.active.order(started_at: :desc)
  end

  def applicable_timezone
    return timezone if timezone.present?

    billing_entity.timezone || "UTC"
  end

  def applicable_invoice_grace_period
    return invoice_grace_period if invoice_grace_period.present?

    billing_entity.invoice_grace_period || 0
  end

  def applicable_net_payment_term
    return net_payment_term if net_payment_term.present?

    billing_entity.net_payment_term
  end

  # `applicable_invoice_custom_sections` includes:
  # - all manually selected (configurable) sections
  # - plus any system-generated sections
  # These are the ones that will actually appear on the invoice.
  def applicable_invoice_custom_sections
    InvoiceCustomSection.where(id: configurable_invoice_custom_sections)
      .or(InvoiceCustomSection.where(id: system_generated_invoice_custom_sections))
  end

  # `configurable_invoice_custom_sections` are manually selected sections:
  # - either directly configured on the customer
  # - or fallback to selections at the billing entity level if none on the customer
  def configurable_invoice_custom_sections
    return InvoiceCustomSection.none if skip_invoice_custom_sections?

    manual_selected_invoice_custom_sections.order(:name).presence || billing_entity.selected_invoice_custom_sections.order(:name)
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

    billing_entity.document_locale.to_sym
  end

  def provider_customer
    case payment_provider&.to_sym
    when :stripe
      stripe_customer
    when :gocardless
      gocardless_customer
    when :cashfree
      cashfree_customer
    when :flutterwave
      flutterwave_customer
    when :adyen
      adyen_customer
    when :moneyhash
      moneyhash_customer
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
    invoices.non_self_billed.payment_overdue.where(currency:).sum(:total_amount_cents)
  end

  def reset_dunning_campaign!
    update!(
      last_dunning_campaign_attempt: 0,
      last_dunning_campaign_attempt_at: nil
    )
  end

  def flag_wallets_for_refresh
    wallets.active.update_all(ready_to_be_refreshed: true) # rubocop:disable Rails/SkipsModelValidations
  end

  def tax_customer
    anrok_customer || avalara_customer
  end

  private

  def ensure_slug
    return if slug.present?

    formatted_sequential_id = format("%03d", sequential_id)

    self.slug = "#{organization.document_number_prefix}-#{formatted_sequential_id}"
  end
end

# == Schema Information
#
# Table name: customers
#
#  id                               :uuid             not null, primary key
#  account_type                     :enum             default("customer"), not null
#  address_line1                    :string
#  address_line2                    :string
#  city                             :string
#  country                          :string
#  currency                         :string
#  customer_type                    :enum
#  deleted_at                       :datetime
#  document_locale                  :string
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
#  payment_receipt_counter          :bigint           default(0), not null
#  phone                            :string
#  shipping_address_line1           :string
#  shipping_address_line2           :string
#  shipping_city                    :string
#  shipping_country                 :string
#  shipping_state                   :string
#  shipping_zipcode                 :string
#  skip_invoice_custom_sections     :boolean          default(FALSE), not null
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
#  billing_entity_id                :uuid             not null
#  external_id                      :string           not null
#  external_salesforce_id           :string
#  organization_id                  :uuid             not null
#  sequential_id                    :bigint
#
# Indexes
#
#  index_customers_on_account_type                     (account_type)
#  index_customers_on_applied_dunning_campaign_id      (applied_dunning_campaign_id)
#  index_customers_on_billing_entity_id                (billing_entity_id)
#  index_customers_on_deleted_at                       (deleted_at)
#  index_customers_on_external_id_and_organization_id  (external_id,organization_id) UNIQUE WHERE (deleted_at IS NULL)
#  index_customers_on_organization_id                  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (applied_dunning_campaign_id => dunning_campaigns.id)
#  fk_rails_...  (billing_entity_id => billing_entities.id)
#  fk_rails_...  (organization_id => organizations.id)
#
