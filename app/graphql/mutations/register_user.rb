# frozen_string_literal: true

module Mutations
  class RegisterUser < BaseMutation
    description 'Registers a new user and creates related organization'

    argument :email, String, required: true
    argument :password, String, required: true
    argument :organization_name, String, required: true

    type Types::Payloads::RegisterUserType

    def resolve(email:, password:, organization_name:)
      result = UsersService.new.register(
        email,
        password,
        organization_name
      )

      result.success? ? result : execution_error(code: result.error_code, message: result.error)
    end
  end
end
