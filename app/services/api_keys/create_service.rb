# frozen_string_literal: true

module ApiKeys
  class CreateService < BaseService
    def initialize(params)
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?

      api_key = ApiKey.create!(
        params.slice(:organization_id, :name)
      )

      ApiKeyMailer.with(api_key:).created.deliver_later

      result.api_key = api_key
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :params
  end
end
