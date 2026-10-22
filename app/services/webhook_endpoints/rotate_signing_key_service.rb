# frozen_string_literal: true

module WebhookEndpoints
  class RotateSigningKeyService < BaseService
    Result = BaseResult[:signing_key]

    # How long the previous keys keep signing after a rotation, so consumers have time to
    # pick up the new public key before the old one stops being used.
    DEFAULT_GRACE_PERIOD = 24.hours

    def initialize(webhook_endpoint:, grace_period: DEFAULT_GRACE_PERIOD)
      @webhook_endpoint = webhook_endpoint
      @grace_period = grace_period

      super
    end

    def call
      ActiveRecord::Base.transaction do
        webhook_endpoint.signing_keys.usable.update_all(expires_at: grace_period.from_now) # rubocop:disable Rails/SkipsModelValidations
        result.signing_key = webhook_endpoint.signing_keys.create!(organization: webhook_endpoint.organization)
      end

      result
    end

    private

    attr_reader :webhook_endpoint, :grace_period
  end
end
