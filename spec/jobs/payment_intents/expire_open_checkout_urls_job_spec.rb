# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentIntents::ExpireOpenCheckoutUrlsJob do
  let(:invoice) { create(:invoice) }

  describe "#perform" do
    it "calls the expire service" do
      allow(PaymentIntents::ExpireOpenCheckoutUrlsService).to receive(:call!)
        .and_return(BaseService::Result.new)

      described_class.new.perform(invoice)

      expect(PaymentIntents::ExpireOpenCheckoutUrlsService).to have_received(:call!).with(invoice:)
    end
  end

  describe "retry behavior" do
    let(:registered_retry_classes) do
      described_class.rescue_handlers.map { |klass_name, _| klass_name }
    end

    it "retries on Lago-wrapped transient provider failures" do
      expect(registered_retry_classes).to include(
        "Invoices::Payments::ConnectionError",
        "Invoices::Payments::RateLimitError"
      )
    end
  end
end
