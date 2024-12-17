# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::CreateService, type: :service do
  subject(:create_service) { described_class.new(payable: payment_request, payment_provider:) }

  let(:payment_request) do
    create(:payment_request, customer:, organization: customer.organization)
  end
  let(:customer) { create(:customer, payment_provider:) }

  describe "#call" do
    context "with adyen payment provider" do
      let(:payment_provider) { "adyen" }
      let(:service_instance) { instance_double(PaymentRequests::Payments::AdyenService) }
      let(:service_result) { BaseService::Result.new }

      before do
        allow(PaymentRequests::Payments::AdyenService).to receive(:new)
          .with(payment_request)
          .and_return(service_instance)
        allow(service_instance).to receive(:create)
          .and_return(service_result)
      end

      it 'creates an adyen payment' do
        result = create_service.call

        expect(result).to eq(service_result)

        expect(PaymentRequests::Payments::AdyenService).to have_received(:new)
          .with(payment_request)
        expect(service_instance).to have_received(:create)
      end

      it "does not send a payment requested email" do
        expect { create_service.call }
          .not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end

      context "when the payment fails" do
        let(:service_result) do
          BaseService::Result.new.tap do |result|
            result.payable = instance_double(PaymentRequest, payment_failed?: true)
          end
        end

        it "sends a payment requested email" do
          expect { create_service.call }
            .to have_enqueued_mail(PaymentRequestMailer, :requested)
            .with(params: {payment_request:}, args: [])
        end
      end
    end

    context "with gocardless payment provider" do
      let(:payment_provider) { "gocardless" }
      let(:service_instance) { instance_double(PaymentRequests::Payments::GocardlessService) }
      let(:service_result) { BaseService::Result.new }

      before do
        allow(PaymentRequests::Payments::GocardlessService).to receive(:new)
          .with(payment_request)
          .and_return(service_instance)
        allow(service_instance).to receive(:create)
          .and_return(service_result)
      end

      it 'creates an adyen payment' do
        result = create_service.call

        expect(result).to eq(service_result)

        expect(PaymentRequests::Payments::GocardlessService).to have_received(:new)
          .with(payment_request)
        expect(service_instance).to have_received(:create)
      end

      it "does not send a payment requested email" do
        expect { create_service.call }
          .not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end

      context "when the payment fails" do
        let(:service_result) do
          BaseService::Result.new.tap do |result|
            result.payable = instance_double(PaymentRequest, payment_failed?: true)
          end
        end

        it "sends a payment requested email" do
          expect { create_service.call }
            .to have_enqueued_mail(PaymentRequestMailer, :requested)
            .with(params: {payment_request:}, args: [])
        end
      end
    end

    context "with stripe payment provider" do
      let(:payment_provider) { "stripe" }
      let(:service_instance) { instance_double(PaymentRequests::Payments::StripeService) }
      let(:service_result) { BaseService::Result.new }

      before do
        allow(PaymentRequests::Payments::StripeService).to receive(:new)
          .with(payment_request)
          .and_return(service_instance)
        allow(service_instance).to receive(:create)
          .and_return(service_result)
      end

      it 'creates an adyen payment' do
        result = create_service.call

        expect(result).to eq(service_result)

        expect(PaymentRequests::Payments::StripeService).to have_received(:new)
          .with(payment_request)
        expect(service_instance).to have_received(:create)
      end

      it "does not send a payment requested email" do
        expect { create_service.call }
          .not_to have_enqueued_mail(PaymentRequestMailer, :requested)
      end

      context "when the payment fails" do
        let(:service_result) do
          BaseService::Result.new.tap do |result|
            result.payable = instance_double(PaymentRequest, payment_failed?: true)
          end
        end

        it "sends a payment requested email" do
          expect { create_service.call }
            .to have_enqueued_mail(PaymentRequestMailer, :requested)
            .with(params: {payment_request:}, args: [])
        end
      end
    end
  end

  describe "#call_async" do
    context "with adyen payment provider" do
      let(:payment_provider) { "adyen" }

      it "enqueues a job to create a adyen payment" do
        expect do
          create_service.call_async
        end.to have_enqueued_job(PaymentRequests::Payments::CreateJob)
      end
    end

    context "with gocardless payment provider" do
      let(:payment_provider) { "gocardless" }

      it "enqueues a job to create a gocardless payment" do
        expect do
          create_service.call_async
        end.to have_enqueued_job(PaymentRequests::Payments::CreateJob)
      end
    end

    context "with strip payment provider" do
      let(:payment_provider) { "stripe" }

      it "enqueues a job to create a stripe payment" do
        expect do
          create_service.call_async
        end.to have_enqueued_job(PaymentRequests::Payments::CreateJob)
      end
    end
  end
end
