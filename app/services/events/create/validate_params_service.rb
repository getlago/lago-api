# frozen_string_literal: true

module Events
  module Create
    class ValidateParamsService
      ALL_REQUIRED_PARAMS = %i[transaction_id code].freeze
      ONE_REQUIRED_PARAMS = %i[external_subscription_id external_customer_id].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(organization:, params:)
        @organization = organization
        @params = params
      end

      def call
        mandatory_params_errors
          .merge(metric_not_found_error)
          .merge(customer_not_found_error)
          .merge(properties_not_valid_errors)
      end

      private

      attr_reader :organization, :params

      def mandatory_params_errors
        errors = ALL_REQUIRED_PARAMS.each_with_object({}) do |key, error|
          error[key] = ['value_is_mandatory'] if params[key].blank?
        end
        errors[:base] = ['missing_external_identifier'] if ONE_REQUIRED_PARAMS.all? { |k| params[k].blank? }

        # NOTE: In case of multiple subscriptions, we return an error if subscription_id is not given.
        if params[:external_customer_id].present? && params[:external_subscription_id].blank?
          customer = organization.customers.find_by(external_id: params[:external_customer_id])
          subscriptions_count = customer ? customer.active_subscriptions.count : 0
          errors[:external_subscription_id] = ['value_is_mandatory'] if subscriptions_count > 1
        end
        errors
      end

      def properties_not_valid_errors
        return {} unless metric
        return {} unless metric.max_agg? || metric.sum_agg?
        return {} if valid_number?(field_name_value)

        { field_name => ['value_is_not_valid_number'] }
      end

      def metric
        @metric ||= organization.billable_metrics.find_by(code: params[:code])
      end

      def metric_not_found_error
        return {} if params[:code].blank? || metric

        { code: ['metric_not_found'] }
      end

      def customer_not_found_error
        return {} if organization.subscriptions.find_by(external_id: params[:external_subscription_id])&.customer
        return {} if Customer.find_by(external_id: params[:external_customer_id], organization_id: organization.id)

        { external_id: ['customer_not_found'] }
      end

      def field_name
        @field_name ||= metric.field_name.to_sym
      end

      def field_name_value
        @field_name_value ||= params[:properties][field_name]
      end

      def valid_number?(value)
        true if Float(value)
      rescue ArgumentError
        false
      end
    end
  end
end
