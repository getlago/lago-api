# frozen_string_literal: true

class Credit < ApplicationRecord
  include Currencies

  belongs_to :invoice
  belongs_to :applied_coupon, optional: true
  belongs_to :credit_note, optional: true

  has_one :coupon, through: :applied_coupon

  validates :amount_currency, inclusion: { in: currency_list }

  scope :coupon_kind, -> { where.not(applied_coupon_id: nil) }
  scope :credit_note_kind, -> { where.not(credit_note_id: nil) }

  def item_id
    return coupon&.id if applied_coupon_id

    credit_note.id
  end

  def item_type
    return 'coupon' if applied_coupon_id?

    'credit_note'
  end

  def item_code
    return coupon&.code if applied_coupon_id?

    credit_note.number
  end

  def item_name
    return coupon&.name if applied_coupon_id?

    # TODO: change it depending on invoice template
    credit_note.invoice.number
  end
end
