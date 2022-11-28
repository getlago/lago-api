# frozen_string_literal: true

class InvoiceSubscription < ApplicationRecord
  include CustomerTimezone

  belongs_to :invoice
  belongs_to :subscription

  has_one :customer, through: :subscription

  # NOTE: Readonly fields
  monetize :charge_amount_cents, disable_validation: true, allow_nil: true
  monetize :subscription_amount_cents, disable_validation: true, allow_nil: true
  monetize :total_amount_cents, disable_validation: true, allow_nil: true

  def fees
    @fees ||= Fee.where(
      subscription_id: subscription.id,
      invoice_id: invoice.id,
    )
  end

  def from_datetime
    fees_datetime('from_datetime')&.to_datetime
  end

  def to_datetime
    fees_datetime('to_datetime')&.to_datetime
  end

  def charges_from_datetime
    fees_datetime('charges_from_datetime')&.to_datetime
  end

  def charges_to_datetime
    fees_datetime('charges_to_datetime')&.to_datetime
  end

  def charge_amount_cents
    fees.charge_kind.sum(:amount_cents)
  end

  def subscription_amount_cents
    fees.subscription_kind.first&.amount_cents || 0
  end

  def total_amount_cents
    charge_amount_cents + subscription_amount_cents
  end

  def total_amount_currency
    subscription.plan.amount_currency
  end

  alias charge_amount_currency total_amount_currency
  alias subscription_amount_currency total_amount_currency

  def fees_datetime(field)
    return if fees.empty?

    fees.first.properties[field]
  end
end
