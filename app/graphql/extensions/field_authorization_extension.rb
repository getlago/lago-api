# frozen_string_literal: true

module Extensions
  class FieldAuthorizationExtension < GraphQL::Schema::FieldExtension
    def apply
      pp :APPLY
      super
    end

    def resolve(object:, arguments:, context:)
      pp field.permission
      pp context[:current_user].email

      return nil if field.permission

      x = super
      pp x
      x
    end
  end
end
