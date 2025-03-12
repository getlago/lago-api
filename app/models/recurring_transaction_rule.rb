# frozen_string_literal: true

class RecurringTransactionRule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet

  STATUSES = [
    :active,
    :terminated
  ].freeze

  INTERVALS = [
    :weekly,
    :monthly,
    :quarterly,
    :yearly
  ].freeze

  METHODS = [
    :fixed,
    :target
  ].freeze

  TRIGGERS = [
    :interval,
    :threshold
  ].freeze

  enum :interval, INTERVALS
  enum :method, METHODS
  enum :trigger, TRIGGERS
  enum :status, STATUSES

  def mark_as_terminated!(timestamp = Time.zone.now)
    self.terminated_at ||= timestamp
    terminated!
  end

  scope :active, -> { where(status: statuses[:active]).where("expiration_at IS NULL OR expiration_at > ?", Time.current) }
  scope :eligible_for_termination, -> {
    where(status: statuses[:active])
      .where("expiration_at IS NOT NULL AND expiration_at <= ?", Time.current)
  }
  scope :expired, -> { where("recurring_transaction_rules.expiration_at::timestamp(0) <= ?", Time.current) }
end

# == Schema Information
#
# Table name: recurring_transaction_rules
#
#  id                                  :uuid             not null, primary key
#  expiration_at                       :datetime
#  granted_credits                     :decimal(30, 5)   default(0.0), not null
#  interval                            :integer          default("weekly")
#  invoice_requires_successful_payment :boolean          default(FALSE), not null
#  method                              :integer          default("fixed"), not null
#  paid_credits                        :decimal(30, 5)   default(0.0), not null
#  started_at                          :datetime
#  status                              :integer          default("active")
#  target_ongoing_balance              :decimal(30, 5)
#  terminated_at                       :datetime
#  threshold_credits                   :decimal(30, 5)   default(0.0)
#  transaction_metadata                :jsonb
#  trigger                             :integer          default("interval"), not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  wallet_id                           :uuid             not null
#
# Indexes
#
#  index_recurring_transaction_rules_on_expiration_at  (expiration_at)
#  index_recurring_transaction_rules_on_started_at     (started_at)
#  index_recurring_transaction_rules_on_wallet_id      (wallet_id)
#
# Foreign Keys
#
#  fk_rails_...  (wallet_id => wallets.id)
#
