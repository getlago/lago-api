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
            COALESCE(
              (invoice_subscriptions.properties->>\'to_datetime\')::timestamp, invoice_subscriptions.created_at
            ) ASC
          SQL

          order(Arel.sql(ActiveRecord::Base.sanitize_sql_for_conditions(condition)))
        }

  scope :recurring, -> { where(recurring: true) }

  def fees
    @fees ||= Fee.where(
      subscription_id: subscription.id,
      invoice_id: invoice.id,
    )
  end

  def from_datetime
    properties['from_datetime']&.to_datetime
  end

  def to_datetime
    properties['to_datetime']&.to_datetime
  end

  def charges_from_datetime
    properties['charges_from_datetime']&.to_datetime
  end

  def charges_to_datetime
    properties['charges_to_datetime']&.to_datetime
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
end
