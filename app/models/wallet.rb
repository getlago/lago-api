# frozen_string_literal: true

class Wallet < ApplicationRecord
  belongs_to :customer

  STATUSES = [
    :active,
    :expired,
  ].freeze

  enum status: STATUSES
end
