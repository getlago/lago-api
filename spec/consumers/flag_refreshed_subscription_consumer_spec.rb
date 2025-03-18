# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FlagRefreshedSubscriptionsConsumer, type: :consumer do
  let(:consumer) { karafka.consumer_for(ENV["LAGO_KAFKA_REFRESHED_SUBSCRIPTIONS_TOPIC"]) }

  let(:message) { {"subscription_id" => SecureRandom.uuid} }

  before { karafka.produce(message.to_json) }

  it "enqueues a flag refreshed subscription job" do
    expect { consumer.consume }.to have_enqueued_job(Subscriptions::FlagRefreshedJob).with(message)
  end
end
