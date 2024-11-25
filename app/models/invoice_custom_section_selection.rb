# frozen_string_literal: true

class InvoiceCustomSectionSelection < ApplicationRecord
  belongs_to :ginvoice_custom_section
  belongs_to :organization, optional: true
  belongs_to :customer, optional: true
end

# == Schema Information
#
# Table name: invoice_custom_section_selections
#
#  id                        :uuid             not null, primary key
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  customer_id               :uuid
#  invoice_custom_section_id :uuid             not null
#  organization_id           :uuid
#
# Indexes
#
#  idx_on_invoice_custom_section_id_7edbcef7b5                 (invoice_custom_section_id)
#  index_invoice_custom_section_selections_on_customer_id      (customer_id)
#  index_invoice_custom_section_selections_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#  fk_rails_...  (invoice_custom_section_id => invoice_custom_sections.id)
#  fk_rails_...  (organization_id => organizations.id)
#
