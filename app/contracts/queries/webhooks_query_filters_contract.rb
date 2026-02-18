# frozen_string_literal: true

module Queries
  class WebhooksQueryFiltersContract < Dry::Validation::Contract
    params do
      required(:webhook_endpoint_id).filled(:string)

      optional(:status).maybe do
        value(:string, included_in?: Webhook::STATUS.map(&:to_s)) |
          array(:string, included_in?: Webhook::STATUS.map(&:to_s))
      end
    end
  end
end
