# frozen_string_literal: true

module Organizations
  class UpdateService < BaseService
    def initialize(organization)
      @organization = organization

      super(nil)
    end

    def update(**args)
      organization.update!(webhook_url: args[:webhook_url])
      result.organization = organization

      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_reader :organization
  end
end
