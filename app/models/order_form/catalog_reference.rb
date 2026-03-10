# frozen_string_literal: true

class OrderForm
  class CatalogReference < ApplicationRecord
    self.primary_key = %i[order_form_id referenced_type referenced_id]

    belongs_to :order_form
    belongs_to :organization

    validates :referenced_type, presence: true
    validates :referenced_id, presence: true
  end
end

# == Schema Information
#
# Table name: order_form_catalog_references
# Database name: primary
#
#  referenced_type :string           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  order_form_id   :uuid             not null, primary key
#  organization_id :uuid             not null
#  referenced_id   :uuid             not null, primary key
#
# Indexes
#
#  index_order_form_catalog_references_on_order_form_id           (order_form_id)
#  index_order_form_catalog_references_on_organization_id         (organization_id)
#  index_order_form_catalog_references_on_referenced_type_and_id  (referenced_type,referenced_id)
#
# Foreign Keys
#
#  fk_rails_...  (order_form_id => order_forms.id)
#  fk_rails_...  (organization_id => organizations.id)
#
