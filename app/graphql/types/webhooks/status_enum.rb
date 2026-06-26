# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Webhooks
    class StatusEnum < Types::BaseEnum
      graphql_name "WebhookStatusEnum"

      Webhook::STATUS.each do |type|
        value type
      end
    end
  end
end
