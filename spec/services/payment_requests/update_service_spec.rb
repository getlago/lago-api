# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::UpdateService do
  subject(:result) do
    described_class.call(
      payable: payment_request,
      params: update_args,
      webhook_notification:
    )
  end

  let(:payment_request) { create :payment_request }
  let(:webhook_notification) { false }
  let(:update_args) { {payment_status: "succeeded"} }

  describe "#call" do
    before do
      allow(SegmentTrackJob).to receive(:perform_later)
    end

    it "updates the invoice", :aggregate_failures do
      expect(result).to be_success
      expect(result.payable).to eq(payment_request)
      expect(result.payable).to be_payment_succeeded
    end

    it "calls SegmentTrackJob" do
      result

      expect(SegmentTrackJob).to have_received(:perform_later).with(
        membership_id: CurrentContext.membership,
        event: "payment_status_changed",
        properties: {
          organization_id: payment_request.organization.id,
          payment_request_id: payment_request.id,
          payment_status: payment_request.payment_status
        }
      )
    end

    context "when payment_request does not exist" do
      let(:payment_request) { nil }

      it "returns an error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("payment_request_not_found")
      end
    end
  end
end
