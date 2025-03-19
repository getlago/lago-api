# frozen_string_literal: true

class Charge
  class AppliedTax < ApplicationRecord
    self.table_name = "charges_taxes"

    belongs_to :charge
    belongs_to :tax
  end
end

# == Schema Information
#
# Table name: charges_taxes
#
#  id         :uuid             not null, primary key
#  charge_id  :uuid             not null
#  tax_id     :uuid             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_charges_taxes_on_charge_id             (charge_id)
#  index_charges_taxes_on_charge_id_and_tax_id  (charge_id,tax_id) UNIQUE
#  index_charges_taxes_on_tax_id                (tax_id)
#
