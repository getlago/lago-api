# frozen_string_literal: true

class Fee < ApplicationRecord
  include Currencies

  belongs_to :invoice
  belongs_to :charge, optional: true
  belongs_to :subscription

  has_one :customer, through: :subscription
  has_one :organization, through: :invoice
  has_one :billable_metric, through: :charge

  monetize :amount_cents
  monetize :vat_amount_cents

  validates :amount_currency, inclusion: { in: currency_list }
  validates :vat_amount_currency, inclusion: { in: currency_list }
  validates :units, numericality: { greated_than_or_equal_to: 0 }

  scope :subscription_kind, -> { where(charge_id: nil) }
  scope :charge_kind, -> { where.not(charge_id: nil) }

  def subscription_fee?
    charge_id.blank?
  end

  def charge_fee?
    charge_id.present?
  end

  def compute_vat
    self.vat_amount_cents = (amount_cents * vat_rate).fdiv(100).ceil
    self.vat_amount_currency = amount_currency
  end

  def item_type
    return 'charge' if charge_fee?

    'subscription'
  end

  def item_code
    return billable_metric.code if charge_fee?

    subscription.plan.code
  end

  def item_name
    return billable_metric.name if charge_fee?

    subscription.plan.name
  end
end
