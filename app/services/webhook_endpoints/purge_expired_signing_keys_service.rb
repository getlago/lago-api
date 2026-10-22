# frozen_string_literal: true

module WebhookEndpoints
  class PurgeExpiredSigningKeysService < BaseService
    Result = BaseResult[:purged_count]

    def call
      result.purged_count = WebhookEndpointSigningKey.expired.delete_all
      result
    end
  end
end
