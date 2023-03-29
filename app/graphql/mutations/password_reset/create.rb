# frozen_string_literal: true

module Mutations
  module PasswordReset
    class Create < BaseMutation
      graphql_name 'CreatePasswordReset'
      description 'Creates a new PasswordReset'

      argument :email, String, required: true
      field :id, String, null: false

      def resolve(email:)
        user = User.find_by(email:)
        result = ::PasswordReset::CreateService.call(user:)

        result.success? ? result : result_error(result)
      end
    end
  end
end
