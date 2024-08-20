# frozen_string_literal: true

class Commitment
  class AppliedTax < ApplicationRecord
    self.table_name = 'commitments_taxes'

    belongs_to :commitment
    belongs_to :tax
  end
end

# == Schema Information
#
# Table name: commitments_taxes
#
#  id            :uuid             not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  commitment_id :uuid             not null
#  tax_id        :uuid             not null
#
# Indexes
#
#  index_commitments_taxes_on_commitment_id  (commitment_id)
#  index_commitments_taxes_on_tax_id         (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (commitment_id => commitments.id)
#  fk_rails_...  (tax_id => taxes.id)
#
