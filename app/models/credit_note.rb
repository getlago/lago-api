# frozen_string_literal: true

class CreditNote < ApplicationRecord
  include Sequenced

  before_save :ensure_number

  belongs_to :customer
  belongs_to :invoice

  has_one :organization, through: :customer

  has_many :items, class_name: 'CreditNoteItem'
  has_many :fees, through: :items

  has_one_attached :file

  monetize :total_amount_cents
  monetize :credit_amount_cents
  monetize :balance_amount_cents

  CREDIT_STATUS = %i[available consumed].freeze
  REASON = %i[duplicated_charge product_unsatisfactory order_change order_cancellation fraudulent_charge other].freeze

  enum credit_status: CREDIT_STATUS
  enum reason: REASON

  sequenced scope: ->(credit_note) { CreditNote.where(invoice_id: credit_note.invoice_id) }

  validates :total_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :credit_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :balance_amount_cents, numericality: { greater_than_or_equal_to: 0 }

  def file_url
    return if file.blank?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: ENV['LAGO_API_URL'])
  end

  private

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{invoice.number}-CN#{formatted_sequential_id}"
  end
end
