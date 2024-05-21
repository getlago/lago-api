# frozen_string_literal: true

class RecurringTransactionRule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet

  INTERVALS = [
    :weekly,
    :monthly,
    :quarterly,
    :yearly
  ].freeze

  METHODS = [
    :fixed,
    :target
  ].freeze

  TRIGGERS = [
    :interval,
    :threshold
  ].freeze

  enum interval: INTERVALS
  enum method: METHODS
  enum trigger: TRIGGERS
end
