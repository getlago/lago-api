# frozen_string_literal: true

module Metadata
  class InvoiceMetadata < ApplicationRecord
    COUNT_PER_INVOICE = 5

    belongs_to :invoice

    validates :key, presence: true, uniqueness: {scope: :invoice_id}, length: {maximum: 20}
    validates :value, presence: true
  end
end
