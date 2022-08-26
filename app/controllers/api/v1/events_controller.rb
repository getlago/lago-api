# frozen_string_literal: true

module Api
  module V1
    class EventsController < Api::BaseController
      def create
        validate_result = Events::CreateService.new.validate_params(params: create_params)
        return validation_errors(validate_result) unless validate_result.success?

        Events::CreateJob.perform_later(
          current_organization,
          create_params,
          Time.zone.now.to_i,
          event_metadata,
        )

        head(:ok)
      end

      def batch
        validate_result = Events::CreateBatchService.new.validate_params(params: batch_params)
        return validation_errors(validate_result) unless validate_result.success?

        Events::CreateBatchJob.perform_later(
          current_organization,
          batch_params,
          Time.zone.now.to_i,
          event_metadata,
        )

        head(:ok)
      end

      def show
        event = Event.find_by(
          organization: current_organization,
          transaction_id: params[:id]
        )

        return not_found_error unless event

        render(
          json: ::V1::EventSerializer.new(
            event,
            root_name: 'event',
          )
        )
      end

      private

      def create_params
        params
          .require(:event)
          .permit(
            :transaction_id,
            :external_customer_id,
            :code,
            :timestamp,
            :external_subscription_id,
            properties: {},
          )
      end

      def batch_params
        params
          .require(:event)
          .permit(
            :transaction_id,
            :external_customer_id,
            :code,
            :timestamp,
            external_subscription_ids: [],
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
