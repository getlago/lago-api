# frozen_string_literal: true

module Metadata
  class InvoiceMetadata < ApplicationRecord
    belongs_to :invoice

    validates :key, presence: true, uniqueness: { scope: :invoice_id }, length: { maximum: 20 }
    validates :value, presence: true
  end
end
