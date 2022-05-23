# frozen_string_literal: true

module Mutations
  module AddOns
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name 'DestroyAddOn'
      description 'Deletes an add-on'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = ::AddOns::DestroyService.new(context[:current_user]).destroy(id)

        result.success? ? result.add_on : result_error(result)
      end
    end
  end
end
