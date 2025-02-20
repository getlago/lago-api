# frozen_string_literal: true

class BillingEntity
  class AppliedTax < ApplicationRecord
    self.table_name = "billing_entities_taxes"

    belongs_to :billing_entity
    belongs_to :tax
  end
end

# == Schema Information
#
# Table name: billing_entities_taxes
#
#  id                :uuid             not null, primary key
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  billing_entity_id :uuid             not null
#  tax_id            :uuid             not null
#
# Indexes
#
#  index_billing_entities_taxes_on_billing_entity_id             (billing_entity_id)
#  index_billing_entities_taxes_on_billing_entity_id_and_tax_id  (billing_entity_id,tax_id) UNIQUE
#  index_billing_entities_taxes_on_tax_id                        (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (billing_entity_id => billing_entities.id)
#  fk_rails_...  (tax_id => taxes.id)
#
