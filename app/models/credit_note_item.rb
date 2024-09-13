# frozen_string_literal: true

class CreditNoteItem < ApplicationRecord
  belongs_to :credit_note
  belongs_to :fee

  monetize :amount_cents

  validates :amount_cents, numericality: {greater_than_or_equal_to: 0}

  def applied_taxes
    credit_note.applied_taxes.where(tax_code: fee.applied_taxes.select('fees_taxes.tax_code'))
  end
end

# == Schema Information
#
# Table name: credit_note_items
#
#  id                   :uuid             not null, primary key
#  amount_cents         :bigint           default(0), not null
#  amount_currency      :string           not null
#  precise_amount_cents :decimal(30, 5)   not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  credit_note_id       :uuid             not null
#  fee_id               :uuid
#
# Indexes
#
#  index_credit_note_items_on_credit_note_id  (credit_note_id)
#  index_credit_note_items_on_fee_id          (fee_id)
#
# Foreign Keys
#
#  fk_rails_...  (credit_note_id => credit_notes.id)
#  fk_rails_...  (fee_id => fees.id)
#
