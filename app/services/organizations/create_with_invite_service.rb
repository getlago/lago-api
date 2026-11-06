# frozen_string_literal: true

module Organizations
  class CreateWithInviteService < BaseService
    Result = BaseResult[:organization, :sandbox_organization, :invite_url]

    def initialize(name:, owner_email:, document_numbering:, timezone: nil, premium_integrations: [], self_serve: false)
      @name = name
      @owner_email = owner_email
      @document_numbering = document_numbering
      @timezone = timezone
      @premium_integrations = premium_integrations
      @self_serve = self_serve
      super()
    end

    def call
      unless [true, false].include?(self_serve)
        return result.single_validation_failure!(field: :self_serve, error_code: "value_is_invalid")
      end
      # Pairs exist only where the self-serve mirroring and login rules run.
      return result.forbidden_failure!(code: "self_serve_disabled") if self_serve && !Lago::SelfServe.enabled?

      ActiveRecord::Base.transaction do
        if self_serve
          # A pair takes the numbering of self-serve signup.
          pair = CreateSelfServeService.call!(name:, timezone:, premium_integrations:)
          result.organization = pair.organization
          result.sandbox_organization = pair.sandbox_organization
        else
          result.organization = CreateService.call!(
            name:, timezone:, document_numbering:, premium_integrations:
          ).organization
        end

        # On production only: the sandbox gets the owner when the invite is accepted.
        result.invite_url = Invites::CreateService.call!(
          current_organization: result.organization,
          email: owner_email,
          roles: %w[admin],
          skip_admin_check: true
        ).invite_url
      end

      result
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :name, :owner_email, :document_numbering, :timezone, :premium_integrations, :self_serve
  end
end
