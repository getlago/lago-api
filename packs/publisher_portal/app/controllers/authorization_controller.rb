# frozen_string_literal: true

require 'aws_avp'

class AuthorizationController < ApplicationController
  def index
    client = AwsAvp.init
    schema = client.get_schema({
      policy_store_id: "QgU3JUDgJzFADbWzUxUFFJ"
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
