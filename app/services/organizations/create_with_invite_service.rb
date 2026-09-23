# frozen_string_literal: true

module Organizations
  class CreateWithInviteService < BaseService
    Result = BaseResult[:organization, :invite_url]

    def initialize(name:, owner_email:, document_numbering:, timezone: nil, premium_integrations: [])
      @name = name
      @owner_email = owner_email
      @document_numbering = document_numbering
      @timezone = timezone
      @premium_integrations = premium_integrations
      super()
    end

    def call
      ActiveRecord::Base.transaction do
        result.organization = CreateService.call!(
          name:, timezone:, document_numbering:, premium_integrations:
        ).organization

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

    attr_reader :name, :owner_email, :document_numbering, :timezone, :premium_integrations
  end
end
