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

  scope :subscription_kind, -> { where(charge_id: nil) }

  def subscription_fee?
    charge_id.blank?
  end

  def charge_fee?
    charge_id.present?
  end

  def compute_vat
    self.vat_amount_cents = (amount_cents * vat_rate / 100).to_i
    self.vat_amount_currency = amount_currency
  end
end
