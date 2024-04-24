# frozen_string_literal: true

# Mutations::BaseMutation Mutation
module Mutations
  class BaseMutation < GraphQL::Schema::RelayClassicMutation
    include ExecutionErrorResponder
    argument_class Types::BaseArgument
    field_class Types::BaseField
    input_object_class Types::BaseInputObject
    object_class Types::BaseObject

    private

    def ready?(**args)
      if defined? self.class::REQUIRED_PERMISSION
        context.dig(:permissions, self.class::REQUIRED_PERMISSION)
      else
        super
      end
    end
  end
end
