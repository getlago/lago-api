# frozen_string_literal: true

class AppliedInvoiceCustomSection < ApplicationRecord
  belongs_to :invoice
end

# == Schema Information
#
# Table name: applied_invoice_custom_sections
#
#  id           :uuid             not null, primary key
#  code         :string           not null
#  details      :string
#  display_name :string
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  invoice_id   :uuid             not null
#
# Indexes
#
#  index_applied_invoice_custom_sections_on_invoice_id  (invoice_id)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#
