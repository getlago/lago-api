# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CreatePayInAdvanceFixedChargesJob do
  subject(:perform_now) { described_class.perform_now(subscription, timestamp) }

  let(:subscription) { create(:subscription) }
  let(:timestamp) { Time.current.to_i }

  before do
    allow(Invoices::CreatePayInAdvanceFixedChargesService).to receive(:call!)
      .with(subscription:, timestamp:)
  end

  it "calls the create pay in advance fixed charges service" do
    perform_now

    expect(Invoices::CreatePayInAdvanceFixedChargesService).to have_received(:call!)
  end

  [
    [Customers::FailedToAcquireLock.new("customer-1"), 25]
  ].each do |error, attempts|
    error_class = error.class

    context "when a #{error_class} error is raised" do
      before do
        allow(Invoices::CreatePayInAdvanceFixedChargesService).to receive(:call!).and_raise(error)
      end

      it "raises a #{error_class.class.name} error and retries" do
        assert_performed_jobs(attempts, only: [described_class]) do
          expect do
            described_class.perform_later(subscription, timestamp)
          end.to raise_error(error_class)
        end
      end
    end
  end
end
