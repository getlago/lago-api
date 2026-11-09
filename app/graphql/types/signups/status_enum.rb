# frozen_string_literal: true

module Types
  module Signups
    class StatusEnum < Types::BaseEnum
      graphql_name "SignupStatusEnum"

      %w[pending verified expired invalid].each { value it }
    end
  end
end
