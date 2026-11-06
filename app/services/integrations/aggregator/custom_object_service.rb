# frozen_string_literal: true

module Integrations
  module Aggregator
    class CustomObjectService < BaseService
      Result = BaseResult[:custom_object]

      CustomObject = Data.define(:id, :object_type_id)

      def initialize(integration:, name:)
        @name = name
        super(integration:)
      end

      def action_name
        "fetch-custom-object"
      end

      def call
        throttle!(:hubspot)

        response = JSON.parse(trigger_action(body).body)

        result.custom_object = CustomObject.new(id: response["id"], object_type_id: response["objectTypeId"])
        result
      rescue LagoHttpClient::HttpError => e
        result.service_failure!(code: e.error_code, message: e.message)
      end

      private

      attr_reader :name

      def body
        {
          "name" => name
        }
      end
    end
  end
end
