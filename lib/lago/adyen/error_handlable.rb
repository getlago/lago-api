# frozen_string_literal: true

module Lago
  module Adyen
    module ErrorHandlable
      def handle_adyen_response(res)
        return if res.status < 400

        code = res.response['errorType']
        message = res.response['message']

        deliver_error_webhook(::Adyen::AdyenError.new(nil, nil, message, code))
        result.service_failure!(code:, message:)
      end
    end
  end
end
