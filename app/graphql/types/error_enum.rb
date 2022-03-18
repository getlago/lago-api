# frozen_string_literal: true

module Types
  class ErrorEnum < BaseEnum
    # Generic errors
    value 'internal_error'
    value 'unauthorized'
    value 'forbidden'
    value 'not_found'

    # Authentication & authentication errors
    value 'token_encoding_error'
    value 'expired_jwt_token'
    value 'incorrect_login_or_password'
    value 'not_organization_member'

    # Validation errors
    value 'user_already_exists'
  end
end
