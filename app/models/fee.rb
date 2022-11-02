# frozen_string_literal: true

class Fee < ApplicationRecord
  include Currencies

  belongs_to :invoice
  belongs_to :charge, optional: true
  belongs_to :applied_add_on, optional: true
  belongs_to :subscription, optional: true
  belongs_to :group, optional: true
  belongs_to :invoiceable, polymorphic: true, optional: true

  has_one :customer, through: :subscription
  has_one :organization, through: :invoice
  has_one :billable_metric, through: :charge
  has_one :add_on, through: :applied_add_on

  has_many :credit_note_items
  has_many :credit_notes, through: :credit_note_items

  monetize :amount_cents
  monetize :vat_amount_cents
  monetize :total_amount_cents

  FEE_TYPES = %i[charge add_on subscription credit].freeze

  enum fee_type: FEE_TYPES

  validates :amount_currency, inclusion: { in: currency_list }
  validates :vat_amount_currency, inclusion: { in: currency_list }
  validates :units, numericality: { greated_than_or_equal_to: 0 }
  validates :events_count, numericality: { greated_than_or_equal_to: 0 }, allow_nil: true

  scope :subscription_kind, -> { where(fee_type: :subscription) }
  scope :charge_kind, -> { where(fee_type: :charge) }

  def compute_vat
    self.vat_amount_cents = (amount_cents * vat_rate).fdiv(100).ceil
    self.vat_amount_currency = amount_currency
  end

  def item_code
    return billable_metric.code if charge?
    return add_on.code if add_on?
    return fee_type if credit?

    subscription.plan.code
  end

  def item_name
    return billable_metric.name if charge?
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
end
