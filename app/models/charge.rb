# frozen_string_literal: true

class Charge < ApplicationRecord
  include Currencies

  belongs_to :plan
  belongs_to :billable_metric

  has_many :fees

  FREQUENCIES = %i[
    one_time
    recurring
  ].freeze

  CHARGE_MODELS = %i[
    standard
  ].freeze

  enum frequency: FREQUENCIES
  enum charge_model: CHARGE_MODELS

  monetize :amount_cents

  validates :amount_currency, inclusion: { in: currency_list }
end
