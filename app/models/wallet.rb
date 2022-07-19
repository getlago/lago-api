# frozen_string_literal: true

class Wallet < ApplicationRecord
  belongs_to :customer

  has_one :organization, through: :customer

  STATUSES = [
    :active,
    :terminated,
  ].freeze

  enum status: STATUSES
end
