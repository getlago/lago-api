# frozen_string_literal: true

module Metadata
  class CustomerMetadata < ApplicationRecord
    belongs_to :customer

    validates :key, presence: true, uniqueness: { scope: :customer_id }, length: { maximum: 20 }
    validates :value, presence: true, length: { maximum: 40 }
  end
end
