# frozen_string_literal: true

module Api
  module V1
    class EventsController < Api::BaseController
      def create
        validate_result = EventsService.new.validate_params(params: create_params)
        return validation_errors(validate_result) unless validate_result.success?

        CreateEventJob.perform_later(
          current_organization,
          create_params,
          Time.zone.now.to_i,
          event_metadata,
        )

        head(:ok)
      end

      private

      def create_params
        params
          .require(:event)
          .permit(
            :transaction_id,
            :customer_id,
            :code,
            :timestamp,
            properties: {},
          )
      end

      def event_metadata
        {
          user_agent: request.user_agent,
          ip_address: request.remote_ip,
        }
      end
    end
  end
end
