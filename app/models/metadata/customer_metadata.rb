# frozen_string_literal: true

module Metadata
  class CustomerMetadata < ApplicationRecord
    COUNT_PER_CUSTOMER = 5

    belongs_to :customer

    validates :key, presence: true, uniqueness: {scope: :customer_id}, length: {maximum: 20}
    validates :value, presence: true, length: {maximum: 40}

    scope :displayable, -> { where(display_in_invoice: true) }
  end
end
