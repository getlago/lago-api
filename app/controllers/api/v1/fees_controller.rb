# frozen_string_literal: true

module Api
  module V1
    class FeesController < Api::BaseController
      def show
        # NOTE: instant fees might not be linked to any invoice, but add_on fees does not have any subscriptions
        #       so we need a bit of logic to find the fee in the right organization scope
        fee = Fee.left_joins(:invoice)
          .left_joins(subscription: :customer)
          .where('COALESCE(invoices.organization_id, customers.organization_id) = ?', current_organization.id)
          .find_by(id: params[:id])

        return not_found_error(resource: 'fee') unless fee

        render(json: ::V1::FeeSerializer.new(fee, root_name: 'fee'))
      end
    end
  end
end
