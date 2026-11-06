# frozen_string_literal: true

module Organizations
  # Copies a production organization's premium integrations, feature flags and authentication methods to its
  # sandbox, so the sandbox never accepts a weaker login nor gets features its production lacks. A full overwrite,
  # idempotent; `changes` lists, per setting, what was added and removed.
  class SyncSandboxSettingsService < BaseService
    Result = BaseResult[:sandbox_organization, :changes]

    SETTINGS = %i[premium_integrations feature_flags authentication_methods].freeze

    def initialize(organization:, actor: nil)
      @organization = organization
      @actor = actor
      super
    end

    def call
      result.changes = {}
      return result unless organization.production?

      ActiveRecord::Base.transaction do
        # A fresh instance read under the lock: the caller's object can predate a toggle committed meanwhile, and
        # copying from it would undo that toggle on the sandbox.
        locked = SandboxLockService.call!(organization: Organization.find(organization.id), lock_sandbox: true)
        sandbox = locked.sandbox_organization
        next unless sandbox

        copy(locked.organization, sandbox)
        result.sandbox_organization = sandbox
      end

      result
    end

    private

    attr_reader :organization, :actor

    def copy(production, sandbox)
      wanted = {
        premium_integrations: production.premium_integrations,
        feature_flags: production.feature_flags.select { FeatureFlag.valid?(it) },
        authentication_methods: production.authentication_methods
      }

      SETTINGS.each do |setting|
        added = wanted[setting] - sandbox.public_send(setting)
        removed = sandbox.public_send(setting) - wanted[setting]
        result.changes[setting] = {added:, removed:} if added.any? || removed.any?
      end
      return if result.changes.empty?

      sandbox.update!(wanted)
      log_authentication_methods(sandbox) if result.changes.key?(:authentication_methods)
      after_commit { ApiKeys::CacheService.expire_all_cache(sandbox) }
    end

    def log_authentication_methods(sandbox)
      change = result.changes[:authentication_methods]
      user = actor || Membership.find_by(id: CurrentContext.membership.to_s.split("/").last)&.user

      after_commit do
        Utils::SecurityLog.produce(
          organization: sandbox,
          log_type: "organization",
          log_event: "organization.authentication_methods_updated",
          user:,
          resources: {authentication_methods: {deleted: change[:removed].presence, added: change[:added].presence}.compact}
        )
      end
    end
  end
end
