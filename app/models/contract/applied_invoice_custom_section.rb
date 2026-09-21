# frozen_string_literal: true

class Contract::AppliedInvoiceCustomSection < ApplicationRecord
  self.table_name = "contracts_invoice_custom_sections"

  belongs_to :organization
  belongs_to :contract
  belongs_to :invoice_custom_section
end

# == Schema Information
#
# Table name: contracts_invoice_custom_sections
# Database name: primary
#
#  id                        :uuid             not null, primary key
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  contract_id               :uuid             not null
#  invoice_custom_section_id :uuid             not null
#  organization_id           :uuid             not null
#
# Indexes
#
#  idx_on_invoice_custom_section_id_227386d639                 (invoice_custom_section_id)
#  index_contracts_invoice_custom_sections_on_contract_id      (contract_id)
#  index_contracts_invoice_custom_sections_on_organization_id  (organization_id)
#  index_contracts_invoice_custom_sections_unique              (contract_id,invoice_custom_section_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (invoice_custom_section_id => invoice_custom_sections.id)
#  fk_rails_...  (organization_id => organizations.id)
#
