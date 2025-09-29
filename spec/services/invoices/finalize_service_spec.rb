# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::FinalizeService do
  subject(:service) { described_class.new(invoice:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:invoice) { create(:invoice, :draft, customer:, organization:) }

  describe "#call" do
    context "when invoice is not yet finalized" do
      it "finalizes the invoice" do
        result = service.call

        expect(result).to be_success
        expect(result.invoice.status).to eq("finalized")
      end

      it "creates a customer snapshot" do
        expect { service.call }.to change(CustomerSnapshot, :count).by(1)

        snapshot = CustomerSnapshot.last
        expect(snapshot.invoice).to eq(invoice)
        expect(snapshot.organization).to eq(organization)
        expect(snapshot.display_name).to eq(customer.display_name)
      end

      it "saves the invoice" do
        result = service.call

        expect(result.invoice).to be_persisted
        expect(result.invoice.reload.status).to eq("finalized")
      end
    end

    context "when invoice is already finalized" do
      let(:invoice) { create(:invoice, :finalized, customer:, organization:) }

      it "returns success without changes" do
        result = service.call

        expect(result).to be_success
        expect(result.invoice.status).to eq("finalized")
      end

      it "does not create additional customer snapshots" do
        # Create existing snapshot
        create(:customer_snapshot, invoice:, organization:)

        expect { service.call }.not_to change(CustomerSnapshot, :count)
      end
    end

    context "when invoice is nil" do
      let(:invoice) { nil }

      it "returns a not found failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("invoice")
      end
    end

    context "when invoice save fails" do
      before do
        allow(invoice).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invoice))
      end

      it "returns a failure result" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
      end
    end

    context "when customer snapshot creation fails" do
      before do
        allow(CustomerSnapshots::CreateService).to receive(:call!).and_raise(StandardError.new("Snapshot failed"))
      end

      it "rolls back the transaction" do
        expect { service.call }.to raise_error(StandardError, "Snapshot failed")
        expect(invoice.reload.status).not_to eq("finalized")
      end
    end
  end
end
