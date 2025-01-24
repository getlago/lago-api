# frozen_string_literal: true

module QueuesHelper
  def webhook_queue
    if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_WEBHOOK'])
      :webhook_worker
    else
      :webhook
    end
  end
end
