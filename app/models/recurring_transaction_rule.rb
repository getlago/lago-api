# frozen_string_literal: true

class RecurringTransactionRule < ApplicationRecord
  include PaperTrailTraceable

  belongs_to :wallet

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

  enum interval: INTERVALS
  enum method: METHODS
  enum trigger: TRIGGERS
end

# == Schema Information
#
# Table name: recurring_transaction_rules
#
#  id                                 :uuid             not null, primary key
#  granted_credits                    :decimal(30, 5)   default(0.0), not null
#  interval                           :integer          default("weekly")
#  invoice_require_successful_payment :boolean          default(FALSE), not null
#  method                             :integer          default("fixed"), not null
#  paid_credits                       :decimal(30, 5)   default(0.0), not null
#  started_at                         :datetime
#  target_ongoing_balance             :decimal(30, 5)
#  threshold_credits                  :decimal(30, 5)   default(0.0)
#  transaction_metadata               :jsonb
#  trigger                            :integer          default("interval"), not null
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  wallet_id                          :uuid             not null
#
# Indexes
#
#  index_recurring_transaction_rules_on_started_at  (started_at)
#  index_recurring_transaction_rules_on_wallet_id   (wallet_id)
#
# Foreign Keys
#
#  fk_rails_...  (wallet_id => wallets.id)
#
