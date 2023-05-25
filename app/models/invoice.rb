# frozen_string_literal: true

class Invoice < ApplicationRecord
  include PaperTrailTraceable
  include Sequenced
  include RansackUuidSearch

  CREDIT_NOTES_MIN_VERSION = 2
  COUPON_BEFORE_VAT_VERSION = 3

  before_save :ensure_number

  belongs_to :customer, -> { with_discarded }
  belongs_to :organization

  has_many :fees
  has_many :credits
  has_many :wallet_transactions
  has_many :payments
  has_many :invoice_subscriptions
  has_many :subscriptions, through: :invoice_subscriptions
  has_many :plans, through: :subscriptions
  has_many :metadata, class_name: 'Metadata::InvoiceMetadata', dependent: :destroy
  has_many :credit_notes

  has_one_attached :file

  monetize :coupons_amount_cents,
           :credit_notes_amount_cents,
           :fees_amount_cents,
           :prepaid_credit_amount_cents,
           :sub_total_vat_excluded_amount_cents,
           :sub_total_vat_included_amount_cents,
           :total_amount_cents,
           :vat_amount_cents,
           with_model_currency: :currency

  # NOTE: Readonly fields
  monetize :charge_amount_cents,
           :subscription_amount_cents,
           disable_validation: true,
           allow_nil: true,
           with_model_currency: :currency

  INVOICE_TYPES = %i[subscription add_on credit one_off].freeze
  PAYMENT_STATUS = %i[pending succeeded failed].freeze
  STATUS = %i[draft finalized].freeze

  enum invoice_type: INVOICE_TYPES
  enum payment_status: PAYMENT_STATUS
  enum status: STATUS

  sequenced scope: ->(invoice) { invoice.customer.invoices }

  scope :ready_to_be_finalized,
        lambda {
          date = <<-SQL
            (
              invoices.created_at +
              COALESCE(customers.invoice_grace_period, organizations.invoice_grace_period) * INTERVAL '1 DAY'
            )
          SQL

          draft.joins(:customer, :organization).where("#{Arel.sql(date)} < ?", Time.current)
        }

  scope :created_before,
        lambda { |invoice|
          where.not(id: invoice.id)
            .where('invoices.created_at < ?', invoice.created_at)
        }

  validates :issuing_date, :currency, presence: true
  validates :timezone, timezone: true, allow_nil: true

  def file_url
    return if file.blank?

    Rails.application.routes.url_helpers.rails_blob_url(file, host: ENV['LAGO_API_URL'])
  end

  def fee_total_amount_cents
    amount_cents = fees.sum(:amount_cents)
    vat_amount_cents = fees.sum { |f| f.amount_cents * f.vat_rate }.fdiv(100).round
    amount_cents + vat_amount_cents
  end

  def charge_amount_cents
    fees.charge_kind.sum(:amount_cents)
  end

  def subscription_amount_cents
    fees.subscription_kind.sum(:amount_cents)
  end

  def invoice_subscription(subscription_id)
    invoice_subscriptions.find_by(subscription_id:)
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
      group: fee.group,
    ).breakdown(
      from_datetime: DateTime.parse(fee.properties['charges_from_datetime']),
      to_datetime: DateTime.parse(fee.properties['charges_to_datetime']),
    )
    result.breakdown
  end

  def creditable_amount_cents
    return 0 if version_number < CREDIT_NOTES_MIN_VERSION || credit? || draft?

    fees_total_creditable = fees.sum(&:creditable_amount_cents)
    return 0 if fees_total_creditable.zero?

    coupons_adjustement = if version_number < Invoice::COUPON_BEFORE_VAT_VERSION
      0
    else
      coupons_amount_cents.fdiv(fees_amount_cents) * fees_total_creditable
    end

    vat = fees.sum do |fee|
      # NOTE: Because coupons are applied before VAT,
      #       we have to discribute the coupon adjustement at prorata of each fees
      #       to compute the VAT
      fee_rate = fee.creditable_amount_cents.fdiv(fees_total_creditable)
      prorated_coupon_amount = coupons_adjustement * fee_rate
      (fee.creditable_amount_cents - prorated_coupon_amount) * (fee.vat_rate || 0)
    end.fdiv(100).round

    fees_total_creditable - coupons_adjustement + vat
  end

  def refundable_amount_cents
    return 0 if version_number < CREDIT_NOTES_MIN_VERSION || credit? || draft? || !succeeded?

    amount = creditable_amount_cents - credits.where(before_vat: false).sum(:amount_cents) - prepaid_credit_amount_cents
    amount.negative? ? 0 : amount
  end

  private

  def ensure_number
    return if number.present?

    formatted_sequential_id = format('%03d', sequential_id)

    self.number = "#{customer.slug}-#{formatted_sequential_id}"
  end
end
