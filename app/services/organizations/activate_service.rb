# frozen_string_literal: true

module Organizations
  # Opens a self-serve production organization that was waiting for a payment method. Signup sets
  # `activation_status` at creation; this is the only service that changes it afterwards, called by
  # billing-accounts once the customer saved a card, or by a CS admin (`actor`, with a `reason`).
  class ActivateService < BaseService
    Result = BaseResult[:organization, :activated]

    def initialize(organization:, actor: nil, reason: nil)
      @organization = organization
      @actor = actor
      @reason = reason

      super
    end

    def call
      result.activated = false

      ActiveRecord::Base.transaction do
        # Reloads the row, so the checks below read what another transaction committed while this one waited.
        organization.lock!(SandboxLockService::LOCK_MODE)

        if !organization.self_serve? || !organization.production?
          result.forbidden_failure!(code: "organization_not_self_serve_production")
        elsif organization.activation_status_pending_payment_method?
          activate
        end
      end

      result.organization = organization unless result.failure?
      result
    end

    private

    attr_reader :organization, :actor, :reason

    def activate
      # Skips the validations, so a row that a later release made invalid still opens once paid, but keeps the
      # callbacks that record the change in the audit trail. `lock!` reloaded the row: nothing else is dirty.
      organization.update_attribute(:activation_status, Organization::ACTIVATION_STATUSES[:active]) # rubocop:disable Rails/SkipsModelValidations
      result.activated = true

      # The REST gate trusts the API key cache: clear it once the new status is visible to other requests.
      after_commit do
        ApiKeys::CacheService.expire_all_cache(organization)
        Rails.logger.info("Organization #{organization.id} activated")

        Utils::SecurityLog.produce(
          organization:,
          log_type: "organization",
          log_event: "organization.activated",
          user: actor,
          resources: {activated_by: actor ? "cs_admin" : "billing_accounts", reason:}.compact
        )
      end
    end
  end
end
