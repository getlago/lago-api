# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::CreateService, type: :service do
  subject(:create_service) { described_class.new(payment_request) }

  let(:payment_request) do
    create(:payment_request, customer:, organization: customer.organization)
  end
  let(:customer) { create(:customer, payment_provider:) }

  describe "#call" do
    context "with adyen payment provider" do
      let(:payment_provider) { "adyen" }

      it "enqueues a job to create a adyen payment" do
        expect do
          create_service.call
        end.to have_enqueued_job(PaymentRequests::Payments::AdyenCreateJob)
      end
    end

    context "with gocardless payment provider" do
      let(:payment_provider) { "gocardless" }

      it "enqueues a job to create a gocardless payment" do
        expect do
          create_service.call
        end.to have_enqueued_job(PaymentRequests::Payments::GocardlessCreateJob)
      end
    end

    context "with strip payment provider" do
      let(:payment_provider) { "stripe" }

      it "enqueues a job to create a stripe payment" do
        expect do
          create_service.call
        end.to have_enqueued_job(PaymentRequests::Payments::StripeCreateJob)
      end
    end
  end
end
