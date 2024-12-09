# frozen_string_literal: true

class Wallet < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :customer, -> { with_discarded }

  has_one :organization, through: :customer

  has_many :wallet_transactions
  has_many :recurring_transaction_rules

  monetize :balance_cents
  monetize :consumed_amount_cents
  monetize :ongoing_balance_cents, :ongoing_usage_balance_cents, with_model_currency: :balance_currency

  validates :rate_amount, numericality: {greater_than: 0}

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
  scope :ready_to_be_refreshed, -> { where(ready_to_be_refreshed: true) }

  def currency=(currency)
    self.balance_currency = currency
    self.consumed_amount_currency = currency
  end

  def currency
    balance_currency
  end
end

# == Schema Information
#
# Table name: wallets
#
#  id                                  :uuid             not null, primary key
#  balance_cents                       :bigint           default(0), not null
#  balance_currency                    :string           not null
#  consumed_amount_cents               :bigint           default(0), not null
#  consumed_amount_currency            :string           not null
#  consumed_credits                    :decimal(30, 5)   default(0.0), not null
#  credits_balance                     :decimal(30, 5)   default(0.0), not null
#  credits_ongoing_balance             :decimal(30, 5)   default(0.0), not null
#  credits_ongoing_usage_balance       :decimal(30, 5)   default(0.0), not null
#  depleted_ongoing_balance            :boolean          default(FALSE), not null
#  expiration_at                       :datetime
#  invoice_requires_successful_payment :boolean          default(FALSE), not null
#  last_balance_sync_at                :datetime
#  last_consumed_credit_at             :datetime
#  lock_version                        :integer          default(0), not null
#  name                                :string
#  ongoing_balance_cents               :bigint           default(0), not null
#  ongoing_usage_balance_cents         :bigint           default(0), not null
#  rate_amount                         :decimal(30, 5)   default(0.0), not null
#  ready_to_be_refreshed               :boolean          default(FALSE), not null
#  status                              :integer          not null
#  terminated_at                       :datetime
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  customer_id                         :uuid             not null
#
# Indexes
#
#  index_wallets_on_customer_id            (customer_id)
#  index_wallets_on_ready_to_be_refreshed  (ready_to_be_refreshed) WHERE ready_to_be_refreshed
#
# Foreign Keys
#
#  fk_rails_...  (customer_id => customers.id)
#
