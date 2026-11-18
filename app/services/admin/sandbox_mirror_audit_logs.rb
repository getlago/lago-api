# frozen_string_literal: true

module Admin
  # The CS audit rows of the features a sandbox gained or lost when its production's settings were copied onto it, so
  # the sandbox's history and the feature filter show them. Expects `actor` and `reason` readers.
  module SandboxMirrorAuditLogs
    private

    # One [type, key, added] per premium integration or feature flag the copy changed. A flag the copy drops because
    # it no longer exists is cleanup, not a CS change: it gets no row.
    def mirrored_changes(changes)
      {premium_integrations: "premium_integration", feature_flags: "feature_flag"}.flat_map do |setting, type|
        change = changes[setting]
        next [] unless change

        removed = (type == "feature_flag") ? change[:removed].select { FeatureFlag.valid?(it) } : change[:removed]
        change[:added].map { [type, it, true] } + removed.map { [type, it, false] }
      end
    end

    def mirror_audit_logs!(sandbox, changes, batch_id:, rollback_of: nil)
      changes.each do |type, key, added|
        mirror_of = rolled_back_mirror(sandbox, type, key, rollback_of)
        action = if mirror_of
          :rollback
        else
          added ? :toggle_on : :toggle_off
        end

        CsAdminAuditLog.create!(
          actor_user: actor,
          actor_email: actor.email,
          action:,
          organization: sandbox,
          feature_type: type,
          feature_key: key,
          before_value: !added,
          after_value: added,
          reason:,
          rollback_of: mirror_of,
          batch_id:
        )
      end
    end

    # On a rollback, the sandbox row the rolled back change wrote in its batch, so the sandbox's history reads the
    # same as its production's.
    def rolled_back_mirror(sandbox, type, key, rollback_of)
      return unless rollback_of&.batch_id

      CsAdminAuditLog.where(organization: sandbox, batch_id: rollback_of.batch_id, feature_type: type, feature_key: key)
        .where.missing(:rollback).order(:created_at).last
    end
  end
end
