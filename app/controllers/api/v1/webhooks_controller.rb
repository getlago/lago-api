# frozen_string_literal: true

module Api
  module V1
    class WebhooksController < Api::BaseController
      def public_key
        render(plain: RsaPublicKey.to_s)
      end
    end
  end
end
