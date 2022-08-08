# frozen_string_literal: true

class Wallet < ApplicationRecord
  before_create :ensure_customer_currency

  belongs_to :customer

  has_one :organization, through: :customer

  has_many :wallet_transactions

  STATUSES = [
    :active,
    :terminated,
  ].freeze

  enum status: STATUSES

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  private

  def ensure_customer_currency
    self.currency = customer.default_currency
  end
end
