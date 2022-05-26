# frozen_string_literal: true

module Types
  class ErrorEnum < BaseEnum
    # Generic errors
    value 'internal_error', 'An unexpected error occured'
    value 'unauthorized', 'No user authenticated when accessing to a restricted resource'
    value 'forbidden', 'Authenticated user is not allowed to access the resource'
    value 'not_found', 'Resource does not exists'
    value 'unprocessable_entity', 'A validation error occured while processing a mutation on a resource'

    # Authentication & authentication errors
    value 'token_encoding_error', 'Failure while generating a new JWT token'
    value 'expired_jwt_token', 'JWT token has expired'
    value 'incorrect_login_or_password', 'User login or password is invalid'

    # Validation errors
    value 'user_already_exists', 'User already exists in the database.'

    # Customer related errors
    value 'no_active_subscription', 'Customer does not have an active subscription.'
    value 'currencies_does_not_match', 'Currency from customer subscription differs from the provided one.'
    value 'coupon_already_applied', 'Coupon is already applied to the customer'
  end
end
