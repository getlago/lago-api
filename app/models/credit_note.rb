# frozen_string_literal: true

class CreditNote < ApplicationRecord
  include PaperTrailTraceable
  include Sequenced
  include RansackUuidSearch

  DB_PRECISION_SCALE = 5

  before_save :ensure_number

  belongs_to :customer, -> { with_discarded }
  belongs_to :invoice

  has_one :organization, through: :invoice

  has_many :items, class_name: 'CreditNoteItem', dependent: :destroy
  has_many :fees, through: :items
  has_many :refunds

  has_many :applied_taxes, class_name: 'CreditNote::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes
  has_many :integration_resources, as: :syncable

  has_one_attached :file

  monetize :credit_amount_cents
  monetize :balance_amount_cents
  monetize :refund_amount_cents
  monetize :total_amount_cents
  monetize :sub_total_excluding_taxes_amount_cents
  monetize :taxes_amount_cents,
    :coupons_adjustment_amount_cents,
    with_model_currency: :total_amount_currency

  # NOTE: Status of the credit part
  # - available: a credit amount remain available
  # - consumed: the credit amount was totaly consumed
  CREDIT_STATUS = %i[available consumed voided].freeze

  # NOTE: Status of the refund part
  # - pending: the refund is pending for its execution
  # - refunded: the refund has been executed
  # - failed: the refund process has failed
  REFUND_STATUS = %i[pending succeeded failed].freeze

  REASON = %i[duplicated_charge product_unsatisfactory order_change order_cancellation fraudulent_charge other].freeze
  STATUS = %i[draft finalized].freeze

  enum credit_status: CREDIT_STATUS
  enum refund_status: REFUND_STATUS
  enum reason: REASON
  enum status: STATUS

  sequenced scope: ->(credit_note) { CreditNote.where(invoice_id: credit_note.invoice_id) },
    lock_key: ->(credit_note) { credit_note.invoice_id }

  validates :total_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :credit_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :refund_amount_cents, numericality: {greater_than_or_equal_to: 0}
  validates :balance_amount_cents, numericality: {greater_than_or_equal_to: 0}

  def self.ransackable_attributes(_auth_object = nil)
    %w[number id]
  end

  def file_url
    return if file.blank?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: ENV['LAGO_API_URL'])
  end

  def currency
    total_amount_currency
  end

  def credited?
    credit_amount_cents.positive?
  end

  def refunded?
    refund_amount_cents.positive?
  end

  def subscription_ids
    fees.pluck(:subscription_id).uniq
  end

  def subscription_item(subscription_id)
    items.joins(:fee)
      .merge(Fee.subscription)
      .find_by(fees: {subscription_id:}) || Fee.new(amount_cents: 0, amount_currency: currency)
  end

  def subscription_charge_items(subscription_id)
    items.joins(:fee)
      .merge(Fee.charge)
      .where(fees: {subscription_id:})
      .includes(:fee)
  end

  def add_on_items
    items.joins(:fee)
      .merge(Fee.add_on)
      .includes(:fee)
  end

  def should_sync_credit_note?
    finalized? && customer.integration_customers.any? { |c| c.integration.sync_credit_notes }
  end

  def voidable?
    return false if voided?

    balance_amount_cents.positive?
  end

  def mark_as_voided!(timestamp: Time.current)
    update!(
      credit_status: :voided,
      voided_at: timestamp,
      balance_amount_cents: 0,
    )
  end

  def sub_total_excluding_taxes_amount_cents
    (items.sum(&:precise_amount_cents) - precise_coupons_adjustment_amount_cents).round
  end
  alias_method :sub_total_excluding_taxes_amount_currency, :currency

  private

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{invoice.number}-CN#{formatted_sequential_id}"
  end
end
