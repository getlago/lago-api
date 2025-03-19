# frozen_string_literal: true

class AddOn
  class AppliedTax < ApplicationRecord
    self.table_name = "add_ons_taxes"

    belongs_to :add_on
    belongs_to :tax
  end
end

# == Schema Information
#
# Table name: add_ons_taxes
#
#  id         :uuid             not null, primary key
#  add_on_id  :uuid             not null
#  tax_id     :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_add_ons_taxes_on_add_on_id             (add_on_id)
#  index_add_ons_taxes_on_add_on_id_and_tax_id  (add_on_id,tax_id) UNIQUE
#  index_add_ons_taxes_on_tax_id                (tax_id)
#
