# frozen_string_literal: true

module Organizations
  # Turns an existing organization into the sandbox of a production organization, then mirrors production's settings
  # and members onto it. Refuses every link that would leave the target with something production does not mirror:
  # its own SSO, settings the copy would remove, a looser login, pending invites, or members production lacks.
  class LinkSandboxService < BaseService
    Result = BaseResult[:organization, :sandbox_organization]

    LOCK_KEY = "organization_sandbox_link"

    def initialize(production_organization:, sandbox_organization:, actor: nil)
      @production_organization = production_organization
      @sandbox_organization = sandbox_organization
      @actor = actor
      super
    end

    def call
      return result.forbidden_failure!(code: "self_serve_disabled") unless Lago::SelfServe.enabled?
      return result.not_found_failure!(resource: "production_organization") unless production_organization
      return result.not_found_failure!(resource: "sandbox_organization") unless sandbox_organization
      if production_organization.id == sandbox_organization.id
        return result.single_validation_failure!(field: :sandbox_organization_id, error_code: "cannot_link_organization_to_itself")
      end

      ActiveRecord::Base.transaction do
        # Links are rare: serializing them all means two links never wait on each other's rows.
        Organization.with_advisory_lock!(LOCK_KEY, transaction: true, timeout_seconds: 5, disable_query_cache: true) do
          # Refused on committed state before any row lock, so a pair already linked either way is never locked, and
          # the link cannot form a cycle with the production-then-sandbox locks of the mirrors.
          production_organization.reload
          sandbox_organization.reload
          if (code = refusal_code)
            next result.not_allowed_failure!(code:)
          end

          # FOR NO KEY UPDATE, as the mirrors lock: production's own writes (customers, invoices) keep going meanwhile.
          production_organization.lock!(SandboxLockService::LOCK_MODE)
          sandbox_organization.lock!(SandboxLockService::LOCK_MODE)
          # Again on the locked rows, for writers that committed in between.
          if (code = refusal_code)
            next result.not_allowed_failure!(code:)
          end

          link
        end
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ActiveRecord::RecordNotUnique => e
      unique_index_failure!(e, "index_organizations_on_production_organization_id" => :production_organization_id)
    rescue WithAdvisoryLock::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :production_organization, :sandbox_organization, :actor

    def link
      sandbox_organization.update!(environment: "sandbox", production_organization:)
      production_organization.reload_sandbox_organization

      # Settings first: copying custom roles needs the sandbox's custom_roles integration.
      SyncSandboxSettingsService.call!(organization: production_organization, actor:)
      production_organization.active_memberships.includes(:user).find_each do |membership|
        Memberships::SyncSandboxService.call!(organization: production_organization, user: membership.user, actor:)
      end

      after_commit { ApiKeys::CacheService.expire_all_cache(sandbox_organization) }
      result.organization = production_organization
      # The mirrors wrote the settings through another instance of the sandbox.
      result.sandbox_organization = sandbox_organization.reload
    end

    def refusal_code
      production = production_organization
      target = sandbox_organization

      if production.sandbox?
        "production_is_a_sandbox"
      elsif Organization.where.not(id: target.id).exists?(production_organization_id: production.id)
        "production_already_has_sandbox"
      elsif target.sandbox?
        "sandbox_already_linked"
      elsif Organization.exists?(production_organization_id: target.id)
        "sandbox_has_sandbox"
      elsif target.self_serve?
        "sandbox_is_self_serve"
      elsif target.integrations.where(type: AuthenticationMethods::SSO_INTEGRATION_TYPES.values).exists?
        "sandbox_has_sso_integration"
      elsif (target.premium_integrations - production.premium_integrations).any?
        "sandbox_has_extra_premium_integrations"
      elsif (target.feature_flags.select { FeatureFlag.valid?(it) } - production.feature_flags).any?
        "sandbox_has_extra_feature_flags"
      elsif ((production.authentication_methods & AuthenticationMethods::FREE_AUTHENTICATION_METHODS) - target.authentication_methods).any?
        "sandbox_has_stricter_authentication"
      elsif target.invites.pending.exists?
        "sandbox_has_pending_invites"
      elsif target.active_memberships.where.not(user_id: production.active_memberships.select(:user_id)).exists?
        "sandbox_has_other_members"
      end
    end
  end
end
