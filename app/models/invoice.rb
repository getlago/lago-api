# frozen_string_literal: true

class Invoice < ApplicationRecord
  belongs_to :subscription

  has_many :fees

  has_one :customer, through: :subscription
  has_one :organization, through: :subscription
  has_one :plan, through: :subscription

  monetize :amount_cents
  monetize :vat_amount_cents

  before_save :ensure_sequential_id

  validates :from_date, presence: true
  validates :to_date, presence: true
  validates :issuing_date, presence: true
  validate :validate_date_bounds

  scope :with_sequential_id, -> { where.not(sequential_id: nil) }

  private

  def validate_date_bounds
    errors.add(:from_date, 'from_date must be before to_date') if from_date > to_date
  end

  def ensure_sequential_id
    return if sequential_id.present?

    self.sequential_id = generate_sequential_id
  end

  def generate_sequential_id
    sequential_id = organization.invoices.with_sequential_id.order(sequential_id: :desc).limit(1).pluck(:sequential_id).first
    sequential_id ||= 0

    loop do
      sequential_id += 1

      break sequential_id unless organization.invoices.exists?(sequential_id: sequential_id)
    end
  end
end
