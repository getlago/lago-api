# frozen_string_literal: true

class WalletTransaction < ApplicationRecord
  belongs_to :wallet

  STATUSES = [
    :pending,
    :settled,
  ].freeze

  TRANSACTION_TYPES = [
    :inbound,
    :outbound,
  ].freeze

  enum status: STATUSES
  enum transaction_type: TRANSACTION_TYPES
end
