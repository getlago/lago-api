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

  scope :order_by_charges_to_datetime,
        lambda {
          condition = <<-SQL
            COALESCE(invoice_subscriptions.to_datetime, invoice_subscriptions.created_at) DESC
          SQL

          order(Arel.sql(ActiveRecord::Base.sanitize_sql_for_conditions(condition)))
        }

  # NOTE: Billed automatically by the recurring billing process
  #       It is used to prevent double billing on billing day
  scope :recurring, -> { where(recurring: true) }

  def fees
    @fees ||= Fee.where(
      subscription_id: subscription.id,
      invoice_id: invoice.id,
    )
  end

  def charge_amount_cents
    fees.charge_kind.sum(:amount_cents)
  end

  def subscription_amount_cents
    subscription_fee&.amount_cents || 0
  end

  def subscription_fee
    fees.subscription_kind.first
  end

  def total_amount_cents
    charge_amount_cents + subscription_amount_cents
  end

  def total_amount_currency
    subscription.plan.amount_currency
  end

  alias charge_amount_currency total_amount_currency
  alias subscription_amount_currency total_amount_currency
end
