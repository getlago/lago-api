# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Entitlement
    class PrivilegeValueTypeEnum < Types::BaseEnum
      ::Entitlement::Privilege::VALUE_TYPES.each do |value_type|
        value value_type
      end
    end
  end
end
