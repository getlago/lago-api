# frozen_string_literal: true

class Invoice < ApplicationRecord
  include Sequenced

  before_save :ensure_number

  belongs_to :subscription

  has_many :fees
  has_many :credits

  has_one :customer, through: :subscription
  has_one :organization, through: :subscription
  has_one :plan, through: :subscription

  monetize :amount_cents
  monetize :vat_amount_cents

  INVOICE_TYPES = %i[subscription add_on].freeze
  STATUS = %i[pending succeeded failed].freeze

  enum invoice_type: INVOICE_TYPES
  enum status: STATUS

  sequenced scope: ->(invoice) { invoice.customer.invoices }

  validates :from_date, presence: true
  validates :to_date, presence: true
  validates :issuing_date, presence: true
  validate :validate_date_bounds

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
