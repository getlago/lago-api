# frozen_string_literal: true

class Invoice < ApplicationRecord
  include AASM
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

  has_many :applied_taxes, class_name: 'Invoice::AppliedTax', dependent: :destroy
  has_many :taxes, through: :applied_taxes

  has_one_attached :file

  monetize :coupons_amount_cents,
           :credit_notes_amount_cents,
           :fees_amount_cents,
           :prepaid_credit_amount_cents,
           :sub_total_excluding_taxes_amount_cents,
           :sub_total_including_taxes_amount_cents,
           :total_amount_cents,
           :taxes_amount_cents,
           with_model_currency: :currency

  # NOTE: Readonly fields
  monetize :charge_amount_cents,
           :subscription_amount_cents,
           disable_validation: true,
           allow_nil: true,
           with_model_currency: :currency

  INVOICE_TYPES = %i[subscription add_on credit one_off].freeze
  PAYMENT_STATUS = %i[pending succeeded failed].freeze
  STATUS = %i[draft finalized voided].freeze

  enum invoice_type: INVOICE_TYPES
  enum payment_status: PAYMENT_STATUS
  enum status: STATUS

  aasm column: 'status', timestamps: true do
    state :draft
    state :finalized
    state :voided

    event :finalize do
      transitions from: :draft, to: :finalized
    end

    event :void do
      transitions from: :finalized, to: :voided, guard: :voidable?, after: :void_invoice!
    end
  end

  sequenced scope: ->(invoice) { invoice.customer.invoices },
            lock_key: ->(invoice) { invoice.customer_id },
            organization_scope: ->(invoice) { invoice.organization.invoices.where(created_at: Time.now.all_month) }

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
  validates :total_amount_cents, numericality: { greater_than_or_equal_to: 0 }

  def self.ransackable_attributes(_ = nil)
    %w[id number]
  end

  def self.ransackable_associations(_ = nil)
    %w[customer]
  end

  def file_url
    return if file.blank?

    blob_path = Rails.application.routes.url_helpers.rails_blob_path(
      file,
      host: 'void',
    )

    File.join(ENV['LAGO_API_URL'], blob_path)
  end

  def fee_total_amount_cents
    amount_cents = fees.sum(:amount_cents)
    taxes_amount_cents = fees.sum { |f| f.amount_cents * f.taxes_rate }.fdiv(100).round
    amount_cents + taxes_amount_cents
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
    subscription_fees(subscription_id)
      .joins(charge: :billable_metric)
      .where(billable_metric: { recurring: true })
      .where(billable_metric: { aggregation_type: %i[sum_agg unique_count_agg] })
      .where(charge: { pay_in_advance: false })
  end

  def recurring_breakdown(fee)
    service = case fee.charge.billable_metric.aggregation_type.to_sym
              when :sum_agg
                BillableMetrics::Breakdown::SumService
              when :unique_count_agg
                BillableMetrics::Breakdown::UniqueCountService
              else
                raise(NotImplementedError)
    end

    service.new(
      event_store_class: Events::Stores::PostgresStore,
      charge: fee.charge,
      subscription: fee.subscription,
      group: fee.group,
      boundaries: {
        from_datetime: DateTime.parse(fee.properties['charges_from_datetime']),
        to_datetime: DateTime.parse(fee.properties['charges_to_datetime']),
      },
    ).breakdown.breakdown
  end

  def charge_pay_in_advance_proration_range(fee, timestamp)
    date_service = Subscriptions::DatesService.new_instance(
      fee.subscription,
      Time.zone.at(timestamp),
      current_usage: true,
    )

    event = Event.find_by(id: fee.pay_in_advance_event_id)

    return {} unless event

    number_of_days = Utils::DatetimeService.date_diff_with_timezone(
      event.timestamp,
      date_service.charges_to_datetime,
      customer.applicable_timezone,
    )

    {
      number_of_days:,
      period_duration: date_service.charges_duration_in_days,
    }
  end

  def charge_pay_in_advance_interval(timestamp, subscription)
    date_service = Subscriptions::DatesService.new_instance(
      subscription,
      Time.zone.at(timestamp) + 1.day,
      current_usage: true,
    )

    {
      charges_from_date: date_service.charges_from_datetime&.to_date,
      charges_to_date: date_service.charges_to_datetime&.to_date,
    }
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
      (fee.creditable_amount_cents - prorated_coupon_amount) * (fee.taxes_rate || 0)
    end.fdiv(100).round

    fees_total_creditable - coupons_adjustement + vat
  end

  def refundable_amount_cents
    return 0 if version_number < CREDIT_NOTES_MIN_VERSION || credit? || draft? || !succeeded?

    amount = creditable_amount_cents -
             credits.where(before_taxes: false).sum(:amount_cents) -
             prepaid_credit_amount_cents
    amount.negative? ? 0 : amount
  end

  def voidable?
    return false if credit_notes.where.not(credit_status: :voided).any?

    finalized? && (pending? || failed?)
  end

  private

  def void_invoice!
    update!(ready_for_payment_processing: false)
  end

  def ensure_number
    return if number.present?

    if organization.document_numbering.to_s == 'per_customer'
      formatted_sequential_id = format('%03d', sequential_id)

      self.number = "#{customer.slug}-#{formatted_sequential_id}"
    else
      org_formatted_sequential_id = format('%03d', organization_sequential_id)

      self.number =
        "#{organization.document_number_prefix}-#{Time.now.utc.strftime("%Y%m")}-#{org_formatted_sequential_id}"
    end
  end
end
