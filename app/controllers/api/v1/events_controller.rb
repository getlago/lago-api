# frozen_string_literal: true

module Api
  module V1
    class EventsController < Api::BaseController
      def create
        CreateEventJob.perform_later(
          current_organization,
          create_params,
          Time.zone.now.to_i,
        )

        head(:ok)
      end

      private

      def create_params
        params
          .require(:event)
          .permit(
            :customer_id,
            :code,
            :timestamp,
            properties: {},
          )
      end
    end
  end
end
