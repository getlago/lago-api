# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotes::Refunds::StripeCreateJob do
  let(:credit_note) { create(:credit_note) }

  let(:refund_service) do
    instance_double(CreditNotes::Refunds::StripeService)
  end

  it "delegates to the stripe refund service" do
    allow(CreditNotes::Refunds::StripeService).to receive(:new)
      .with(credit_note)
      .and_return(refund_service)
    allow(refund_service).to receive(:create)
      .and_return(CreditNotes::Refunds::StripeService::Result.new)

    described_class.perform_now(credit_note)

    expect(CreditNotes::Refunds::StripeService).to have_received(:new)
    expect(refund_service).to have_received(:create)
  end

  describe "retry_on" do
    PaymentProviders::StripeProvider::TRANSIENT_ERRORS.each do |error_class|
      error = error_class.new("boom")

      context "when a #{error_class} error is raised" do
        before do
          allow(CreditNotes::Refunds::StripeService).to receive(:new).and_return(refund_service)
          allow(refund_service).to receive(:create).and_raise(error)
        end

        it "raises a #{error_class.name} error and retries" do
          assert_performed_jobs(6, only: [described_class]) do
            expect do
              described_class.perform_later(credit_note)
            end.to raise_error(error_class)
          end
        end
      end
    end
  end
end
