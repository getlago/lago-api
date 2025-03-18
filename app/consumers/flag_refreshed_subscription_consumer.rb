# frozen_string_literal: true

class FlagRefreshedSubscriptionConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      Subscriptions::FlagRefreshedJob.perform_later(message.payload)
    end
  end
end
