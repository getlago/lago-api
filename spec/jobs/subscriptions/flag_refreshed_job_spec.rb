# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FlagRefreshedJob, type: :job do
  describe "#perform" do
    let(:subscription_id) { SecureRandom.uuid }

    it "calls the subscriptions flag refreshed job" do
      allow(Subscriptions::FlagRefreshedService).to receive(:call!)

      described_class.perform_now(subscription_id)

      expect(Subscriptions::FlagRefreshedService).to have_received(:call!)
        .with(subscription_id)
    end
  end
end
