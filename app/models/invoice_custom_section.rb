# frozen_string_literal: true

class InvoiceCustomSection < ApplicationRecord
  include Discard::Model
  self.discard_column = :deleted_at

  belongs_to :organization

  validates :name, presence: true
  validates :code, presence: true, uniqueness: {scope: :organization_id}
end

# == Schema Information
#
# Table name: invoice_custom_sections
#
#  id              :uuid             not null, primary key
#  code            :string           not null
#  deleted_at      :datetime
#  description     :string
#  details         :string
#  display_name    :string
#  name            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :uuid             not null
#
# Indexes
#
#  idx_on_organization_id_deleted_at_225e3f789d               (organization_id,deleted_at)
#  index_invoice_custom_sections_on_organization_id           (organization_id)
#  index_invoice_custom_sections_on_organization_id_and_code  (organization_id,code) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#
