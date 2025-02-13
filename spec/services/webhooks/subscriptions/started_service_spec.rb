# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::Subscriptions::StartedService do
  subject(:webhook_service) { described_class.new(object: subscription) }

  let(:subscription) { create(:subscription) }
  let(:organization) { subscription.organization }

  describe ".call" do
    it_behaves_like "creates webhook", "subscription.started", "subscription"
  end
end
