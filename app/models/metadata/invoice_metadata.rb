# frozen_string_literal: true

module Metadata
  class InvoiceMetadata < ApplicationRecord
    COUNT_PER_INVOICE = 5

    belongs_to :invoice

    validates :key, presence: true, uniqueness: {scope: :invoice_id}, length: {maximum: 20}
    validates :value, presence: true
  end
end

# == Schema Information
#
# Table name: invoice_metadata
#
#  id         :uuid             not null, primary key
#  key        :string           not null
#  value      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  invoice_id :uuid             not null
#
# Indexes
#
#  index_invoice_metadata_on_invoice_id          (invoice_id)
#  index_invoice_metadata_on_invoice_id_and_key  (invoice_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#
