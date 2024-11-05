# frozen_string_literal: true

module ApiKeys
  class RotateService < BaseService
    def initialize(api_key)
      @api_key = api_key
      super
    end

    def call
      return result.not_found_failure!(resource: 'api_key') unless api_key

      new_api_key = api_key.organization.api_keys.new

      ActiveRecord::Base.transaction do
        new_api_key.save!
        api_key.update!(expires_at: Time.current)
      end

      ApiKeyMailer.with(api_key:).rotated.deliver_later

      result.api_key = new_api_key
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :api_key
  end
end
