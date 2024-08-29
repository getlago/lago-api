# frozen_string_literal: true

class Fee
  class AppliedTax < ApplicationRecord
    self.table_name = 'fees_taxes'

    include PaperTrailTraceable

    belongs_to :fee
    belongs_to :tax, optional: true
  end
end

# == Schema Information
#
# Table name: fees_taxes
#
#  id                   :uuid             not null, primary key
#  amount_cents         :bigint           default(0), not null
#  amount_currency      :string           not null
#  precise_amount_cents :decimal(40, 15)  default(0.0), not null
#  tax_code             :string           not null
#  tax_description      :string
#  tax_name             :string           not null
#  tax_rate             :float            default(0.0), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  fee_id               :uuid             not null
#  tax_id               :uuid
#
# Indexes
#
#  index_fees_taxes_on_fee_id             (fee_id)
#  index_fees_taxes_on_fee_id_and_tax_id  (fee_id,tax_id) UNIQUE WHERE ((tax_id IS NOT NULL) AND (created_at >= '2023-09-12 00:00:00'::timestamp without time zone))
#  index_fees_taxes_on_tax_id             (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (fee_id => fees.id)
#  fk_rails_...  (tax_id => taxes.id)
#
