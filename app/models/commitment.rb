# frozen_string_literal: true

class Commitment < ApplicationRecord
  belongs_to :plan
  has_many :applied_taxes, class_name: 'Commitment::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  COMMITMENT_TYPES = {
    minimum_commitment: 0,
  }.freeze

  enum commitment_type: COMMITMENT_TYPES

  monetize :amount_cents, disable_validation: true, allow_nil: true

  validates :amount_cents, numericality: { greater_than: 0 }, allow_nil: false
  validates :commitment_type, uniqueness: { scope: :plan_id }
end
