# frozen_string_literal: true

class AppliedInvoiceCustomSection < ApplicationRecord
  belongs_to :invoice
end

# == Schema Information
#
# Table name: applied_invoice_custom_sections
#
#  id           :uuid             not null, primary key
#  name         :string           not null
#  code         :string           not null
#  display_name :string
#  details      :string
#  invoice_id   :uuid             not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_applied_invoice_custom_sections_on_invoice_id  (invoice_id)
#
