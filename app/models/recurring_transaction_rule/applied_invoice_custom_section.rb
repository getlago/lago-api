# frozen_string_literal: true

class Subscription::AppliedInvoiceCustomSection < ApplicationRecord
  self.table_name = "recurring_transaction_rules_invoice_custom_sections"

  belongs_to :organization
  belongs_to :recurring_transaction_rule
  belongs_to :invoice_custom_section
end

# == Schema Information
#
# Table name: applied_invoice_custom_sections
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  details         :string
#  display_name    :string
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  invoice_id      :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_applied_invoice_custom_sections_on_invoice_id       (invoice_id)
#  index_applied_invoice_custom_sections_on_organization_id  (organization_id)
#
# Foreign Keys
#
#  fk_rails_...  (invoice_id => invoices.id)
#  fk_rails_...  (organization_id => organizations.id)
#
