# frozen_string_literal: true

module Types
  module Coupons
    class UpdateInput < Types::Coupons::CreateInput
      graphql_name "UpdateCouponInput"

      argument :id, String, required: true
      argument :code, String, required: false
    end
  end
end
