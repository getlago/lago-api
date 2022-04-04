# frozen_string_literal: true

class Invoice < ApplicationRecord
  belongs_to :subscription

  has_one :customer, through: :subscription
  has_one :organization, through: :subscription
  has_one :plan, through: :subscription
end
