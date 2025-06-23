# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  sidekiq_options retry: 0

  # This method is used to perform a job after a commit.
  #
  # It is meant to avoid race-conditions where a job run before changes are commited to the DB and we end up with stale
  # data in the job.
  #
  # It is also possible to rely on `ActiveJob::Base.enqueue_after_transaction_commit` but this doesn't allow incremental
  # changes.
  #
  # Note that this method is not compatible with configured jobs, e.g.
  # `Invoices::UpdateFeesPaymentStatusJob.set(wait: 30.seconds).perform_later(invoice)`.
  #
  def self.perform_after_commit(...)
    AfterCommitEverywhere.after_commit do
      perform_later(...)
    end
  end
end
