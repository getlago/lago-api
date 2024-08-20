# frozen_string_literal: true

class CreditNote
  class AppliedTax < ApplicationRecord
    self.table_name = 'credit_notes_taxes'

    include PaperTrailTraceable

    belongs_to :credit_note
    belongs_to :tax

    monetize :amount_cents
    monetize :base_amount_cents, with_model_currency: :amount_currency
  end
end

# == Schema Information
#
# Table name: credit_notes_taxes
#
#  id                :uuid             not null, primary key
#  amount_cents      :bigint           default(0), not null
#  amount_currency   :string           not null
#  base_amount_cents :bigint           default(0), not null
#  tax_code          :string           not null
#  tax_description   :string
#  tax_name          :string           not null
#  tax_rate          :float            default(0.0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  credit_note_id    :uuid             not null
#  tax_id            :uuid             not null
#
# Indexes
#
#  index_credit_notes_taxes_on_credit_note_id             (credit_note_id)
#  index_credit_notes_taxes_on_credit_note_id_and_tax_id  (credit_note_id,tax_id) UNIQUE
#  index_credit_notes_taxes_on_tax_id                     (tax_id)
#
# Foreign Keys
#
#  fk_rails_...  (credit_note_id => credit_notes.id)
#  fk_rails_...  (tax_id => taxes.id)
#
