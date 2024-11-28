# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  # TODO: enable this with Rails 8
  # self.enqueue_after_transaction_commit = true

  sidekiq_options retry: 0
end
