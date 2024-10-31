# frozen_string_literal: true

module Mutations
  module ApiKeys
    class Rotate < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = 'developers:keys:manage'

      graphql_name 'RotateApiKey'
      description 'Create new ApiKey while expiring provided'

      argument :id, ID, required: true

      type Types::ApiKeys::Object

      def resolve(id:)
        api_key = context[:current_organization].api_keys.active.find_by(id:)
        result = ::ApiKeys::RotateService.call(api_key)

        result.success? ? result.api_key : result_error(result)
      end
    end
  end
end
