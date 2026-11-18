# frozen_string_literal: true

module Organizations
  # Opens a self-serve production organization that was waiting for a payment method. The only writer of
  # `activation_status`, called by billing-accounts once the customer saved a card.
  class ActivateService < BaseService
    Result = BaseResult[:organization]

    def initialize(organization:)
      @organization = organization

      super
    end

    def call
      return result.not_found_failure!(resource: "organization") unless organization
      unless organization.self_serve? && organization.production?
        return result.forbidden_failure!(code: "organization_not_self_serve_production")
      end

      ActiveRecord::Base.transaction do
        organization.lock!(SandboxLockService::LOCK_MODE)
        activate if organization.activation_status_pending_payment_method?
      end

      result.organization = organization
      result
    end

    private

    attr_reader :organization

    def activate
      organization.update!(activation_status: Organization::ACTIVATION_STATUSES[:active])
      # The REST gate trusts the API key cache: clear it once the new status is visible to other requests.
      after_commit { ApiKeys::CacheService.expire_all_cache(organization) }
      Rails.logger.info("Organization #{organization.id} activated")
    end
  end
end
