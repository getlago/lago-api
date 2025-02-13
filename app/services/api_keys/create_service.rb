# frozen_string_literal: true

module ApiKeys
  class CreateService < BaseService
    def initialize(params)
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless License.premium?

      if params[:permissions].present? && !params[:organization].api_permissions_enabled?
        return result.forbidden_failure!(code: "premium_integration_missing")
      end

      api_key = ApiKey.create!(
        params.slice(:organization, :name, :permissions)
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
