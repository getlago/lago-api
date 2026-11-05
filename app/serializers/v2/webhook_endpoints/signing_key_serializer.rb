# frozen_string_literal: true

module V2
  module WebhookEndpoints
    class SigningKeySerializer < ModelSerializer
      timestamps :created_at

      def serialize
        {lago_id: model.id, secret_key: model.secret_key}
      end
    end
  end
end
