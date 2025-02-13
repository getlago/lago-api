# frozen_string_literal: true

module QueuesHelper
  def webhook_queue
    if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_WEBHOOK"])
      :webhook_worker
    else
      :webhook
    end
  end

  # This performs any enqueued-jobs, and continues doing so until the queue is empty.
  # Lots of the jobs enqueue other jobs as part of their work, and this ensures that
  # everything that's supposed to happen, happens.
  #
  # ⚠️ Notice that `have_been_enqueued` might not work with perform_all_enqueued_jobs
  # because it's only aware of the last run of the loop.
  def perform_all_enqueued_jobs
    until enqueued_jobs.empty?
      perform_enqueued_jobs
      Sidekiq::Worker.drain_all
    end
  end
end
