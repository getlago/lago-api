# frozen_string_literal: true

class FlagRefreshedSubscriptionsConsumer < ApplicationConsumer
  def consume
    messages.each do |message|
      Subscriptions::FlagRefreshedJob.perform_later(message.payload)
    end
  end
end
