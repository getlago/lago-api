# frozen_string_literal: true

module Mutations
  module Integrations
    class Destroy < Base
      graphql_name 'DestroyIntegration'
      description 'Destroy an integration'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = ::Integrations::DestroyService
          .new(context[:current_user])
          .destroy(id:)

        result.success? ? result.integration : result_error(result)
      end
    end
  end
end
