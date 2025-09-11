# frozen_string_literal: true

class RecurringTransactionRule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet
  belongs_to :organization

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

  def apply_top_up_limits(credit_amount:)
    if ignore_paid_top_up_limits?
      credit_amount
    else
      wallet.apply_top_up_limits(credit_amount:)
    end
  end

  def compute_paid_credits(ongoing_balance:)
    if target?
      compute_target_paid_credits(ongoing_balance:)
    else
      paid_credits
    end
  end

  def compute_granted_credits
    if target?
      0.0
    else
      granted_credits
    end
  end

  private

  def compute_target_paid_credits(ongoing_balance:)
    if ongoing_balance >= target_ongoing_balance
      return 0.0
    end

    gap = target_ongoing_balance - ongoing_balance

    apply_top_up_limits(credit_amount: gap)
  end
end

# == Schema Information
#
# Table name: recurring_transaction_rules
#
#  id                                  :uuid             not null, primary key
#  expiration_at                       :datetime
#  granted_credits                     :decimal(30, 5)   default(0.0), not null
#  ignore_paid_top_up_limits           :boolean          default(FALSE), not null
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
#  organization_id                     :uuid             not null
#  wallet_id                           :uuid             not null
#
# Indexes
#
#  index_recurring_transaction_rules_on_expiration_at    (expiration_at)
#  index_recurring_transaction_rules_on_organization_id  (organization_id)
#  index_recurring_transaction_rules_on_started_at       (started_at)
#  index_recurring_transaction_rules_on_wallet_id        (wallet_id)
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (wallet_id => wallets.id)
#
