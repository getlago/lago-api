# frozen_string_literal: true

module ApiKeys
  class FetchService < BaseService
    Result = BaseResult[:api_key, :organization]

    def initialize(auth_token)
      @auth_token = auth_token
      super
    end

    def call
      api_key_json = Rails.cache.read("api_key/#{auth_token}")
      if api_key_json
        data = JSON.parse(api_key_json)
        result.organization = Organization.new(data['organization'].slice(*Organization.column_names))
        result.api_key = ApiKey.new(data['api_key'].slice(*ApiKey.column_names))

        return result
      end

      api_key = ApiKey.includes(:organization).find_by(value: auth_token)

      if api_key
        expiration = if api_key.expires_at
          (api_key.expires_at - Time.current).to_i.seconds
        else
          1.hour
        end

        Rails.cache.write(
          "api_key/#{auth_token}",
          {
            organization: api_key.organization.attributes,
            api_key: api_key.attributes
          }.to_json,
          expires_in: expiration
        )
      end

      result.api_key = api_key
      result.organization = api_key&.organization
      result
    end

    private

    attr_reader :auth_token
  end
end
