# frozen_string_literal: true

module Types
  module WebhookEndpoints
    class EventCategoryEnum < Types::BaseEnum
      WEBHOOK_EVENT_TYPES.values
        .map { |e| e[:category].to_s }
        .uniq
        .each do |category|
          graphql_key = category.parameterize(separator: "_").upcase

          value graphql_key, value: category
      end
    end
  end
end
