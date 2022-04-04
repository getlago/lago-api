# frozen_string_literal: true

class Charge < ApplicationRecord
  belongs_to :plan
  belongs_to :billable_metric

  FREQUENCIES = %i[
    one_time
    recurring
  ].freeze

  CHARGE_MODELS = %i[
    standard
  ].freeze

  enum frequency: FREQUENCIES
  enum charge_model: CHARGE_MODELS
end
