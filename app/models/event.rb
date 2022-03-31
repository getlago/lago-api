# frozen_string_literal: true

class Event < ApplicationRecord
  belongs_to :organization
  belongs_to :customer

  validates :transaction_id, presence: true, uniqueness: { scope: :organization_id }
  validates :code, presence: true
end
