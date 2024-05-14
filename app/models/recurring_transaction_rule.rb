# frozen_string_literal: true

class RecurringTransactionRule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet

  TRIGGERS = [
    :interval,
    :threshold,
  ].freeze

  INTERVALS = [
    :weekly,
    :monthly,
    :quarterly,
    :yearly,
  ].freeze

  enum trigger: TRIGGERS
  enum interval: INTERVALS
end
