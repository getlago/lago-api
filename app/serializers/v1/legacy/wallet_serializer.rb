# frozen_string_literal: true

module V1
  module Legacy
    class WalletSerializer < ModelSerializer
      def serialize
        {
          expiration_date: model.expiration_at&.to_date&.iso8601,
          balance: model.balance.to_s
        }
      end
    end
  end
end
