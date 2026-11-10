# frozen_string_literal: true

module Signups
  # Signup Step 3: creates the production organization of a self-serve user who has none yet, with its sandbox, and
  # makes the user admin of both. The role and source answers go to analytics only and are never stored.
  class CreateOrganizationService < BaseService
    Result = BaseResult[:organization, :sandbox_organization, :user]

    ROLES = %w[engineering finance founder product_management data leadership other].freeze
    SOURCES = %w[ai_search github hacker_news reference y_combinator search_engine other].freeze

    def initialize(user:, name:, role:, referral_source: nil)
      @user = user
      @name = name
      @role = role
      @referral_source = referral_source
      super
    end

    def call
      return result.forbidden_failure!(code: "self_serve_disabled") unless Lago::SelfServe.enabled?
      return result.not_found_failure!(resource: "user") unless user
      return result.single_validation_failure!(field: :role, error_code: "value_is_invalid") unless ROLES.include?(role)
      if referral_source.present? && SOURCES.exclude?(referral_source)
        return result.single_validation_failure!(field: :source, error_code: "value_is_invalid")
      end

      ActiveRecord::Base.transaction do
        # Checked again on the locked user, so two submissions of Step 3 create a single pair.
        user.lock!
        user.memberships.reset
        next result.forbidden_failure!(code: "user_not_eligible") unless user.needs_organization?

        pair = Organizations::CreateSelfServeService.call!(name:)
        membership = create_admin_membership(pair.organization)

        result.organization = pair.organization
        result.sandbox_organization = pair.sandbox_organization
        after_commit { announce(membership, pair.sandbox_organization) }
      end
      return result if result.failure?

      # The memberships were read under the lock, before this one existed: the answer's needsOrganization reads them.
      user.memberships.reset
      result.user = user
      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    # Not `source`: BaseService already names the caller (GraphQL, API) that way.
    attr_reader :user, :name, :role, :referral_source

    # Admin of production, then the sandbox mirrors it, as for every member.
    def create_admin_membership(organization)
      Organizations::SandboxLockService.call!(organization:)
      membership = Membership.create!(user:, organization:)
      MembershipRole.create!(organization:, membership:, role: Role.admins.find_by!(organization_id: nil))
      Memberships::SyncSandboxService.call!(organization:, user:, actor: user)
      membership
    end

    def announce(membership, sandbox)
      Utils::SecurityLog.produce(
        organization: membership.organization,
        log_type: "user",
        log_event: "user.signed_up",
        user:,
        resources: {email: user.email, roles: membership.roles.map(&:code)},
        skip_organization_check: true
      )
      SegmentIdentifyJob.perform_later(membership_id: "membership/#{membership.id}")
      SegmentTrackJob.perform_later(
        membership_id: "membership/#{membership.id}",
        event: "organization_registered",
        # The only place the Step 3 answers go: Lago stores neither, and the job does not log its arguments.
        properties: {
          organization_name: membership.organization.name,
          organization_id: membership.organization_id,
          email: user.email,
          self_serve: true,
          sandbox_organization_id: sandbox.id,
          role:,
          source: referral_source,
          region: URI(Rails.application.config.lago_front_url).host
        }
      )
    end
  end
end
