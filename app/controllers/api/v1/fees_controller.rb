# frozen_string_literal: true

module Api
  module V1
    class FeesController < Api::BaseController
      def show
        fee = current_organization.fees.find_by(id: params[:id])
        return not_found_error(resource: 'fee') unless fee

        render(json: ::V1::FeeSerializer.new(fee, root_name: 'fee'))
      end
    end
  end
end
