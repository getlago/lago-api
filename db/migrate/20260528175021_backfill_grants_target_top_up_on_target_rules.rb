# frozen_string_literal: true

class BackfillGrantsTargetTopUpOnTargetRules < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Local model so the migration stays self-contained. Using the real
  # `RecurringTransactionRule` would couple this migration to the live model:
  # if the enum mapping, validations, or callbacks change later, replaying
  # this migration on a fresh database could behave differently than it did
  # on production. The local class freezes the enum mapping at the values
  # that were in place when the migration was written.
  class RecurringTransactionRule < ApplicationRecord
    self.table_name = "recurring_transaction_rules"
    enum :method, {fixed: 0, target: 1}
  end

  def up
    RecurringTransactionRule.where(method: :target, grants_target_top_up: nil)
      .in_batches(of: 1000)
      .update_all(grants_target_top_up: false) # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    # irreversible
  end
end
