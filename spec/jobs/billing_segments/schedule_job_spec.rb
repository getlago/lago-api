# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingSegments::ScheduleJob do
  it "schedules the customer's due segments" do
    customer = create(:customer)
    allow(BillingSegments::ScheduleService).to receive(:call!)

    described_class.perform_now(customer.id)

    expect(BillingSegments::ScheduleService).to have_received(:call!).with(customer:)
  end
end
