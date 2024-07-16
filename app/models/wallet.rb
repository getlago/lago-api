# frozen_string_literal: true

class Wallet < ApplicationRecord
  class Config < ::Config
    def invoice_require_successful_payment?
      @hash["invoice.require_successful_payment"]
    end

    def invoice_require_successful_payment=(value)
      @hash["invoice.require_successful_payment"] = value
    end

    def default
      {
        invoice: {
          require_successful_payment: false
        }
      }
    end
  end

  include PaperTrailTraceable

  belongs_to :customer, -> { with_discarded }

  has_one :organization, through: :customer

  has_many :wallet_transactions
  has_many :recurring_transaction_rules

  serialize :config, coder: ::Wallet::Config

  monetize :balance_cents, :ongoing_balance_cents, :ongoing_usage_balance_cents
  monetize :consumed_amount_cents

  STATUSES = [
    :active,
    :terminated
  ].freeze

  enum status: STATUSES

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  scope :expired, -> { where('wallets.expiration_at::timestamp(0) <= ?', Time.current) }

  def currency=(currency)
    self.balance_currency = currency
    self.consumed_amount_currency = currency
  end

  def currency
    balance_currency
  end
end
