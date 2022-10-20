# frozen_string_literal: true

class Invoice < ApplicationRecord
  include Sequenced

  before_save :ensure_number

  belongs_to :customer

  has_many :fees
  has_many :credits
  has_many :wallet_transactions
  has_many :payments
  has_many :invoice_subscriptions
  has_many :subscriptions, through: :invoice_subscriptions
  has_many :plans, through: :subscriptions
  has_many :credit_notes

  has_one_attached :file

  monetize :amount_cents
  monetize :vat_amount_cents
  monetize :credit_amount_cents
  monetize :total_amount_cents

  # NOTE: Readonly fields
  monetize :sub_total_vat_excluded_amount_cents, disable_validation: true, allow_nil: true
  monetize :sub_total_vat_included_amount_cents, disable_validation: true, allow_nil: true
  monetize :coupon_total_amount_cents, disable_validation: true, allow_nil: true
  monetize :credit_note_total_amount_cents, disable_validation: true, allow_nil: true
  monetize :charge_amount_cents, disable_validation: true, allow_nil: true
  monetize :subscription_amount_cents, disable_validation: true, allow_nil: true
  monetize :wallet_transaction_amount_cents, disable_validation: true, allow_nil: true

  INVOICE_TYPES = %i[subscription add_on credit].freeze
  STATUS = %i[pending succeeded failed].freeze

  enum invoice_type: INVOICE_TYPES
  enum status: STATUS

  sequenced scope: ->(invoice) { invoice.customer.invoices }

  validates :issuing_date, presence: true

  def file_url
    return if file.blank?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: ENV['LAGO_API_URL'])
  end

  def fee_total_amount_cents
    fees.sum(:amount_cents) + fees.sum(:vat_amount_cents)
  end

  def currency
    amount_currency
  end

  def sub_total_vat_excluded_amount_cents
    fees.sum(:amount_cents)
  end
  alias sub_total_vat_excluded_amount_currency currency

  def sub_total_vat_included_amount_cents
    sub_total_vat_excluded_amount_cents + vat_amount_cents
  end
  alias sub_total_vat_included_amount_currency currency

  def coupon_total_amount_cents
    credits.coupon_kind.sum(:amount_cents)
  end
  alias coupon_total_amount_currency currency

  def credit_note_total_amount_cents
    credits.credit_note_kind.sum(:amount_cents)
  end
  alias credit_notes_total_amount_currency currency

  def charge_amount_cents
    fees.charge_kind.sum(:amount_cents)
  end
  alias charge_amount_currency currency

  def subscription_amount_cents
    fees.subscription_kind.sum(:amount_cents)
  end
  alias subscription_amount_currency currency

  def wallet_transaction_amount_cents
    transaction_amount = wallet_transactions.sum(:amount)

    currency = amount.currency
    rounded_amount = transaction_amount.round(currency.exponent)

    rounded_amount * currency.subunit_to_unit
  end
  alias wallet_transaction_amount_currency currency

  def subtotal_before_prepaid_credits
    return amount unless wallet_transactions.exists?

    amount + wallet_transaction_amount
  end

  def organization
    customer&.organization
  end

  def invoice_subscription(subscription_id)
    invoice_subscriptions.find_by(subscription_id: subscription_id)
  end

  def subscription_fees(subscription_id)
    invoice_subscription(subscription_id).fees
  end

  def recurring_fees(subscription_id)
    subscription_fees(subscription_id).joins(charge: :billable_metric)
      .merge(BillableMetric.recurring_count_agg)
  end

  def recurring_breakdown(fee)
    result = BillableMetrics::Aggregations::RecurringCountService.new(
      billable_metric: fee.charge.billable_metric,
      subscription: fee.subscription,
    ).breakdown(
      from_date: Date.parse(fee.properties['charges_from_date']),
      to_date: Date.parse(fee.properties['charges_to_date']),
    )
    result.breakdown
  end

  private

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{customer.slug}-#{formatted_sequential_id}"
  end
end
