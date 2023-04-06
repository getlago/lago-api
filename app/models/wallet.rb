# frozen_string_literal: true

class Wallet < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer

  has_one :organization, through: :customer

  has_many :wallet_transactions

  monetize :balance_cents
  monetize :consumed_amount_cents

  STATUSES = [
    :active,
    :terminated,
  ].freeze

  enum status: STATUSES

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  scope :expired, -> { where('wallets.expiration_at::timestamp(0) <= ?', Time.current) }

  def currency=(currency)
    self.balance_currency = currency
    self.consumed_amount_currenty = currency
  end

  def currency
    balance_currency
  end
end
