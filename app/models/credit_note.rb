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
  monetize :refund_amount_cents
  monetize :vat_amount_cents

  # NOTE: Status of the credit part
  # - available: a credit amount remain available
  # - consumed: the credit amount was totaly consumed
  CREDIT_STATUS = %i[available consumed voided].freeze

  # NOTE: Status of the refund part
  # - pending: the refund is pending for its execution
  # - refunded: the refund has been executed
  REFUND_STATUS = %i[pending refunded].freeze

  REASON = %i[duplicated_charge product_unsatisfactory order_change order_cancellation fraudulent_charge other].freeze

  enum credit_status: CREDIT_STATUS
  enum refund_status: REFUND_STATUS
  enum reason: REASON

  sequenced scope: ->(credit_note) { CreditNote.where(invoice_id: credit_note.invoice_id) }

  validates :total_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :credit_amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :balance_amount_cents, numericality: { greater_than_or_equal_to: 0 }

  def file_url
    return if file.blank?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: ENV['LAGO_API_URL'])
  end

  def credited?
    credit_amount_cents.positive?
  end

  def refunded?
    refund_amount_cents.positive?
  end

  def vat_amount_cents
    0 # TODO: Take VAT into account
  end

  def subscription_ids
    fees.pluck(:subscription_id).uniq
  end

  def subscription_item(subscription_id)
    items.joins(:fee)
      .merge(Fee.subscription)
      .find_by(fees: { subscription_id: subscription_id }) || Fee.new
  end

  def subscription_charge_items(subscription_id)
    items.joins(:fee)
      .merge(Fee.charge)
      .where(fees: { subscription_id: subscription_id })
      .includes(:fee)
  end

  def voidable?
    return false if voided?

    balance_amount_cents.positive?
  end

  def mark_as_voided!(timestamp: Time.current)
    update!(
      credit_status: :voided,
      voided_at: timestamp,
    )
  end

  private

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{invoice.number}-CN#{formatted_sequential_id}"
  end
end
