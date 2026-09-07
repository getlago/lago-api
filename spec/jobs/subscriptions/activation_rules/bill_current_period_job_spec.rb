# frozen_string_literal: true

require "rails_helper"

describe Subscriptions::ActivationRules::BillCurrentPeriodJob do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }

  before do
    allow(Subscriptions::ActivationRules::BillCurrentPeriodService).to receive(:call!)
  end

  it "forwards the subscription to the BillCurrentPeriodService" do
    described_class.perform_now(subscription)

    expect(Subscriptions::ActivationRules::BillCurrentPeriodService).to have_received(:call!).with(subscription:)
  end
end
