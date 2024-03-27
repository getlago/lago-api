# frozen_string_literal: true

module V1
  module Legacy
    class CouponSerializer < ModelSerializer
      def serialize
        {
          expiration_date: model.expiration_at&.to_date&.iso8601
        }
      end
    end
  end
end
