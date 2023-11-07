# frozen_string_literal: true

class WalletTransaction < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet
  belongs_to :invoice, optional: true

  STATUSES = [
    :pending,
    :settled,
  ].freeze

  TRANSACTION_TYPES = [
    :inbound,
    :outbound,
  ].freeze

  SOURCES = [
    :manual,
    :interval,
    :threshold,
  ].freeze

  enum status: STATUSES
  enum transaction_type: TRANSACTION_TYPES
  enum source: SOURCES
end
