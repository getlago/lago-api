# frozen_string_literal: true

module Clock
  class WebhooksCleanupJob < ClockJob
    class_attribute :batch_size, default: 1_000 # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    class_attribute :retention_period, default: 90.days # rubocop:disable ThreadSafety/ClassAndModuleAttributes

    def perform
      loop do
        result = Webhook.where(
          id: Webhook.where("updated_at < ?", retention_period.ago).limit(batch_size).select(:id)
        ).delete_all

        break if result < batch_size
      end
    end
  end
end
