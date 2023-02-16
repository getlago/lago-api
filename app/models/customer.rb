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
  has_many :persisted_events

  has_one :stripe_customer, class_name: 'PaymentProviderCustomers::StripeCustomer'
  has_one :gocardless_customer, class_name: 'PaymentProviderCustomers::GocardlessCustomer'

  PAYMENT_PROVIDERS = %w[stripe gocardless].freeze

  default_scope -> { kept }
  sequenced scope: ->(customer) { customer.organization.customers.with_discarded }

  validates :country, country_code: true, unless: -> { country.nil? }
  validates :document_locale, language_code: true, unless: -> { document_locale.nil? }
  validates :currency, inclusion: { in: currency_list }, allow_nil: true
  validates :external_id,
            presence: true,
            uniqueness: { conditions: -> { where(deleted_at: nil) }, scope: :organization_id }
  validates :invoice_grace_period, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_provider, inclusion: { in: PAYMENT_PROVIDERS }, allow_nil: true
  validates :timezone, timezone: true, allow_nil: true
  validates :vat_rate, numericality: { less_than_or_equal_to: 100, greater_than_or_equal_to: 0 }, allow_nil: true

  def active_subscription
    subscriptions.active.order(started_at: :desc).first
  end

  def active_subscriptions
    subscriptions.active.order(started_at: :desc)
  end

  def applicable_vat_rate
    return vat_rate if vat_rate.present?

    organization.vat_rate || 0
  end

  def applicable_timezone
    return timezone if timezone.present?

    organization.timezone || 'UTC'
  end

  def applicable_invoice_grace_period
    return invoice_grace_period if invoice_grace_period.present?

    organization.invoice_grace_period
  end

  def editable?
    subscriptions.none? &&
      applied_add_ons.none? &&
      applied_coupons.where.not(amount_currency: nil).none? &&
      wallets.none?
  end

  def preferred_document_locale
    return document_locale.to_sym if document_locale?

    organization.document_locale.to_sym
  end

  private

  def ensure_slug
    return if slug.present?

    formatted_sequential_id = format('%03d', sequential_id)
    organization_name_substring = organization.name.first(3).upcase
    organization_id_substring = organization.id.last(4).upcase
    organization_slug = "#{organization_name_substring}-#{organization_id_substring}"

    self.slug = "#{organization_slug}-#{formatted_sequential_id}"
  end
end
