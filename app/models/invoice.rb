# frozen_string_literal: true

class Invoice < ApplicationRecord
  belongs_to :subscription

  has_one :customer, through: :subscription
  has_one :organization, through: :subscription
  has_one :plan, through: :subscription

  validates :from_date, presence: true
  validates :to_date, presence: true
  validate :validate_date_bounds

  private

  def validate_date_bounds
    errors.add(:from_date, 'from_date must be before to_date') if from_date > to_date
  end
end
