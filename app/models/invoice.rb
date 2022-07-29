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
  monetize :credit_amount_cents, disable_validation: true, allow_nil: true

  INVOICE_TYPES = %i[subscription add_on].freeze
  STATUS = %i[pending succeeded failed].freeze

  enum invoice_type: INVOICE_TYPES
  enum status: STATUS

  sequenced scope: ->(invoice) { invoice.customer.invoices }

  validates :from_date, presence: true
  validates :to_date, presence: true
  validates :issuing_date, presence: true
  validate :validate_date_bounds

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

  def credit_amount_cents
    credits.sum(:amount_cents)
  end

  def credit_amount_currency
    amount_currency
  end

  def organization
    customer&.organization
  end

  private

  def validate_date_bounds
    errors.add(:from_date, :invalid_date_range) if from_date > to_date
  end

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{customer.slug}-#{formatted_sequential_id}"
  end
end
