# frozen_string_literal: true

class Fee < ApplicationRecord
  include Currencies

  belongs_to :invoice, optional: true
  belongs_to :charge, -> { with_discarded }, optional: true
  belongs_to :applied_add_on, optional: true
  belongs_to :subscription, optional: true
  belongs_to :group, -> { with_discarded }, optional: true
  belongs_to :invoiceable, polymorphic: true, optional: true

  has_one :customer, through: :subscription
  has_one :organization, through: :invoice
  has_one :billable_metric, -> { with_discarded }, through: :charge
  has_one :add_on, -> { with_discarded }, through: :applied_add_on

  has_many :credit_note_items
  has_many :credit_notes, through: :credit_note_items

  monetize :amount_cents
  monetize :vat_amount_cents
  monetize :total_amount_cents

  FEE_TYPES = %i[charge add_on subscription credit instant_charge].freeze
  PAYMENT_STATUS = %i[pending succeeded failed refunded].freeze

  enum fee_type: FEE_TYPES
  enum payment_status: PAYMENT_STATUS

  validates :amount_currency, inclusion: { in: currency_list }
  validates :vat_amount_currency, inclusion: { in: currency_list }
  validates :units, numericality: { greated_than_or_equal_to: 0 }
  validates :events_count, numericality: { greated_than_or_equal_to: 0 }, allow_nil: true

  scope :subscription_kind, -> { where(fee_type: :subscription) }
  scope :charge_kind, -> { where(fee_type: :charge) }

  # NOTE: instant fees are not be linked to any invoice, but add_on fees does not have any subscriptions
  #       so we need a bit of logic to find the fee in the right organization scope
  scope :from_organization,
        lambda { |organization|
          left_joins(:invoice)
            .left_joins(subscription: :customer)
            .where('COALESCE(invoices.organization_id, customers.organization_id) = ?', organization.id)
        }

  def compute_vat
    self.vat_amount_cents = (amount_cents * vat_rate).fdiv(100).round
    self.vat_amount_currency = amount_currency
  end

  def item_id
    return billable_metric.id if charge? || instant_charge?
    return add_on.id if add_on?
    return invoiceable_id if credit?

    subscription_id
  end

  def item_type
    return BillableMetric.name if charge? || instant_charge?
    return AddOn.name if add_on?
    return WalletTransaction.name if credit?

    Subscription.name
  end

  def item_code
    return billable_metric.code if charge? || instant_charge?
    return add_on.code if add_on?
    return fee_type if credit?

    subscription.plan.code
  end

  def item_name
    return billable_metric.name if charge? || instant_charge?
    return add_on.name if add_on?
    return fee_type if credit?

    subscription.plan.name
  end

  def currency
    amount_currency
  end

  def total_amount_cents
    amount_cents + vat_amount_cents
  end
  alias total_amount_currency currency

  def creditable_amount_cents
    amount_cents - credit_note_items.sum(:amount_cents)
  end
end
