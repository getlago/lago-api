# frozen_string_literal: true

module UsageMonitoring
  module Alerts
    class CreateBatchService < BaseService
      Result = BaseResult[:alerts, :errors]

      def initialize(organization:, subscription:, alerts_params:)
        @organization = organization
        @subscription = subscription
        @alerts_params = alerts_params
        super
      end

      def call
        return result.not_found_failure!(resource: "organization") unless organization
        return result.not_found_failure!(resource: "subscription") unless subscription

        if alerts_params.blank?
          return result.single_validation_failure!(error_code: "no_alerts", field: :alerts)
        end

        result.alerts = []
        result.errors = {}

        ActiveRecord::Base.transaction do
          alerts_params.each_with_index do |alert_params, index|
            ActiveRecord::Base.transaction(requires_new: true) do
              create_result = CreateAlertService.call(
                organization:,
                subscription:,
                params: alert_params.to_h
              )

              if create_result.success?
                result.alerts << create_result.alert
              else
                error_details = {}
                error_details[:params] = alert_params
                error_details[:errors] = if create_result.error.respond_to?(:messages)
                  create_result.error.messages
                else
                  create_result.error&.message
                end
                result.errors[index] = error_details
                raise ActiveRecord::Rollback
              end
            end
          end

          raise ActiveRecord::Rollback if result.errors.any?
        end

        if result.errors.any?
          result.alerts = []
          return result.validation_failure!(errors: result.errors)
        end

        result
      end

      private

      attr_reader :organization, :subscription, :alerts_params
    end
  end
end
