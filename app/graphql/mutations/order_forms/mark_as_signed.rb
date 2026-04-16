# frozen_string_literal: true

module Mutations
  module OrderForms
    class MarkAsSigned < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "order_forms:sign"

      graphql_name "MarkOrderFormAsSigned"
      description "Mark an order form as signed"

      input_object_class Types::OrderForms::MarkAsSignedInput

      type Types::OrderForms::Object

      def resolve(**args)
        order_form = current_organization.order_forms.find_by(id: args[:id])
        result = ::OrderForms::MarkAsSignedService.call(order_form:, user: context[:current_user])

        result.success? ? result.order_form : result_error(result)
      end
    end
  end
end
