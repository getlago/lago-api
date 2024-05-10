# frozen_string_literal: true

class PolicyController < ApplicationController
  # GET /users or /users.json
  def index
    customer = Customer.first

    render(
      json: {
        policy: 'Entitlements',
        message: 'Success',
        data: customer.to_json,
      },
      status: :ok,
    )
  end
end
