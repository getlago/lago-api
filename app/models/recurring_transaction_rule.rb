# frozen_string_literal: true

class RecurringTransactionRule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet

  RULE_TYPES = [
    :interval,
    :threshold,
  ].freeze

  INTERVALS = [
    :weekly,
    :monthly,
    :quarterly,
    :yearly,
  ].freeze

  enum rule_type: RULE_TYPES
  enum interval: INTERVALS
end
