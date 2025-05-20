# frozen_string_literal: true

module Mutations
  module UsageMonitoring
    module Alerts
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "subscriptions:update"

        graphql_name "CreateSubscriptionAlert"
        description "Creates a new Alert for subscription"

        input_object_class Types::UsageMonitoring::Alerts::CreateInput
        type Types::UsageMonitoring::Alerts::Object

        def resolve(**args)
          result = ::UsageMonitoring::CreateAlertService.call(
            organization: current_organization,
            subscription: current_organization.subscriptions.find(args[:subscription_id]),
            params: args
          )

          result.success? ? result.alert : result_error(result)
        end
      end
    end
  end
end
