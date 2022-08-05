# frozen_string_literal: true

class Invoice < ApplicationRecord
  include Sequenced

  before_save :ensure_number

  belongs_to :customer

  has_many :fees
  has_many :credits
  has_many :payments
  has_many :invoice_subscriptions
  has_many :subscriptions, through: :invoice_subscriptions
  has_many :plans, through: :subscriptions

  has_one_attached :file

  monetize :amount_cents
  monetize :vat_amount_cents
  monetize :total_amount_cents

  # NOTE: Readonly fields
  monetize :charge_amount_cents, disable_validation: true, allow_nil: true
  monetize :subscription_amount_cents, disable_validation: true, allow_nil: true
  monetize :credit_amount_cents, disable_validation: true, allow_nil: true

  INVOICE_TYPES = %i[subscription add_on].freeze
  STATUS = %i[pending succeeded failed].freeze

  enum invoice_type: INVOICE_TYPES
  enum status: STATUS

  sequenced scope: ->(invoice) { invoice.customer.invoices }

  validates :issuing_date, presence: true

  def file_url
    return if file.blank?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: ENV['LAGO_API_URL'])
  end

  def charge_amount_cents
    fees.charge_kind.sum(:amount_cents)
  end

  def charge_amount_currency
    amount_currency
  end

  def subscription_amount_cents
    fees.subscription_kind.sum(:amount_cents)
  end

  def credit_amount_cents
    credits.sum(:amount_cents)
  end

  def credit_amount_currency
    amount_currency
  end

  def organization
    customer&.organization
  end

  def invoice_subscription(subscription_id)
    invoice_subscriptions.find_by(subscription_id: subscription_id)
  end

  def subscription_fees(subscription_id)
    invoice_subscription(subscription_id).fees
  end

  private

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{customer.slug}-#{formatted_sequential_id}"
  end
end
