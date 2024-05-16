# frozen_string_literal: true

class SubscriptionChargeController < ApplicationController
  def index
    subscription_charge = SubscriptionCharge.first

    render(
      json: {
        message: 'Success',
        data: subscription_charge.to_json,
      },
      status: :ok,
    )
  end
end
