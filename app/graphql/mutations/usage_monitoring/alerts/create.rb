# frozen_string_literal: true

module Mutations
  module UsageMonitoring
    module Alerts
      class Create < BaseMutation
        include AuthenticableApiUser
        include RequiredOrganization

        REQUIRED_PERMISSION = "subscriptions:update" # TODO: confirm

        graphql_name "CreateSubscriptionAlert"
        description "Creates a new Alert for subscription"

        argument :alert_type, Types::UsageMonitoring::Alerts::AlertTypeEnum, required: true
        argument :billable_metric_id, ID, required: false
        argument :code, String, required: false
        argument :subscription_id, ID, required: true
        argument :thresholds, [Types::UsageMonitoring::Alerts::ThresholdObject], required: true

        type Types::UsageMonitoring::Alerts::Object

        def resolve(**args)
          result = ::UsageMonitoring::CreateAlertService.call(
            organization: current_organization,
            subscription: current_organization.subscriptions.find(args[:subscription_id]),
            params: args,
            billable_metric: args[:billable_metric_id] ?
              current_organization.billable_metrics.find(args[:billable_metric_id]) :
              nil
          )

          result.success? ? result.alert : result_error(result)
        end
      end
    end
  end
end
