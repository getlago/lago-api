# frozen_string_literal: true

module Organizations
  # Locks an organization, then its sandbox, for a write that changes what a sandbox mirrors. Every such write goes
  # through here, so they all lock in the same mode and order and read `sandbox?` only once the row is locked.
  class SandboxLockService < BaseService
    Result = BaseResult[:organization, :sandbox_organization]

    # Conflicts with itself and with FOR UPDATE, not with the FOR KEY SHARE that inserts of child rows take.
    LOCK_MODE = "FOR NO KEY UPDATE"

    def initialize(organization:, allow_sandbox: false, lock_sandbox: false)
      @organization = organization
      @allow_sandbox = allow_sandbox
      @lock_sandbox = lock_sandbox
      super
    end

    def call
      raise ArgumentError, "must be called inside a transaction" unless ApplicationRecord.connection.transaction_open?

      # Reloads the row, so the checks below see a link committed while it waited.
      organization.lock!(LOCK_MODE)
      return result.forbidden_failure!(code: "sandbox_managed_by_production") if organization.sandbox? && !allow_sandbox

      if lock_sandbox && organization.production?
        result.sandbox_organization = Organization.lock(LOCK_MODE).find_by(production_organization_id: organization.id)
      end

      result.organization = organization
      result
    end

    private

    attr_reader :organization, :allow_sandbox, :lock_sandbox
  end
end
