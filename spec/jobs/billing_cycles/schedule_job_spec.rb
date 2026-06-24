# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::ScheduleJob do
  let(:subscription_product_item) { create(:subscription_product_item) }

  before { allow(BillingCycles::ScheduleService).to receive(:call!) }

  it "calls the schedule service for the subscription product item" do
    described_class.perform_now(subscription_product_item)

    expect(BillingCycles::ScheduleService).to have_received(:call!).with(subscription_product_item:)
  end
end
