# frozen_string_literal: true

# Mutations::BaseMutation Mutation
module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include ExecutionErrorResponder
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    def self.permission(permission)
      @permission = permission
    end

    def ready?(**args)
      if @permission
        context[:permissions][@permission]
      else
        super
      end
    end
  end
end
