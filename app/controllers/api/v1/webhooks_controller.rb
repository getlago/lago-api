# frozen_string_literal: true

module Api
  module V1
    class WebhooksController < Api::BaseController
      def public_key
        render(plain: Base64.encode64(RsaPublicKey.to_s))
      end
    end
  end
end
