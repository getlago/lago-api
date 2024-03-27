# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Payments::CreateService, type: :service do
  subject(:create_service) { described_class.new(invoice) }

  let(:invoice) { create(:invoice, customer:, organization: customer.organization) }
  let(:customer) { create(:customer, payment_provider:) }
  let(:payment_provider) { "stripe" }

  describe "#call" do
    it "enqueues a job to create a stripe payment" do
      expect do
        create_service.call
      end.to have_enqueued_job(Invoices::Payments::StripeCreateJob)
    end

    context "with gocardless payment provider" do
      let(:payment_provider) { "gocardless" }

      it "enqueues a job to create a gocardless payment" do
        expect do
          create_service.call
        end.to have_enqueued_job(Invoices::Payments::GocardlessCreateJob)
      end
    end
  end
end
