# frozen_string_literal: true

class Charge < ApplicationRecord
  include Currencies

  belongs_to :plan
  belongs_to :billable_metric

  has_many :fees

  CHARGE_MODELS = %i[
    standard
  ].freeze

  enum charge_model: CHARGE_MODELS

  monetize :amount_cents

  validates :amount_currency, inclusion: { in: currency_list }
end
