# frozen_string_literal: true

class CreditNote < ApplicationRecord
  include Sequenced

  before_save :ensure_number

  belongs_to :customer
  belongs_to :invoice

  has_many :items, class_name: 'CreditNoteItem'
  has_many :fees, through: :items

  has_one_attached :file

  monetize :amount_cents
  monetize :remaining_amount_cents

  STATUS = %i[available consumed].freeze
  REASON = %i[overpaid].freeze

  enum status: STATUS
  enum reason: REASON

  sequenced scope: ->(credit_note) { CreditNote.where(invoice_id: credit_note.invoice_id) }

  private

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{invoice.number}-CN#{formatted_sequential_id}"
  end
end
