# frozen_string_literal: true

module Webhooks
  module PaymentProviders
    class RequiresActionService < BaseService
      private

      def current_organization
        @current_organization ||= object.organization
      end

    end
  end
end
