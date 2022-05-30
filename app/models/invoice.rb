# frozen_string_literal: true

class Invoice < ApplicationRecord
  include Sequenced

  belongs_to :subscription

  has_many :fees
  has_many :credits

  has_one :customer, through: :subscription
  has_one :organization, through: :subscription
  has_one :plan, through: :subscription

  monetize :amount_cents
  monetize :vat_amount_cents

  sequenced scope: ->(invoice) { invoice.organization.invoices }

  validates :issuing_date, presence: true
  validate :validate_date_bounds, if: :recurring_invoice?

  private

  def validate_date_bounds
    errors.add(:from_date, :invalid_date_range) if from_date > to_date
  end

  def recurring_invoice?
    from_date && to_date
  end
end
