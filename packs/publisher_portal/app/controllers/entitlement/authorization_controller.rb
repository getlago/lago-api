# frozen_string_literal: true

require 'aws_avp'

module Entitlement
  class AuthorizationController < ApplicationController
    def index
      client = AwsAvp.init
      schema = client.get_schema({
        policy_store_id: "C67cCCM1qXiox3Uh6f6JzQ"
      })
      render(
        json: {
          message: 'Success',
          data: schema.to_json,
        },
        status: :ok,
      )
    end
  end
end
