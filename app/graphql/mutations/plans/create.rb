# frozen_string_literal: true

module Mutations
  module Plans
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:create"

      graphql_name "CreatePlan"
      description "Creates a new Plan"

      input_object_class Types::Plans::CreateInput
      type Types::Plans::Object

      def resolve(**args)
        args[:charges].map!(&:to_h)

        result = ::Plans::CreateService.call(args.merge(organization_id: current_organization.id))

        result.success? ? result.plan : result_error(result)
      end
    end
  end
end
