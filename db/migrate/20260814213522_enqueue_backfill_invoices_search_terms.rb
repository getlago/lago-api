# frozen_string_literal: true

class EnqueueBackfillInvoicesSearchTerms < ActiveRecord::Migration[8.0]
  def up
    DatabaseMigrations::BackfillInvoicesSearchTermsJob.perform_later
  end

  def down
  end
end
