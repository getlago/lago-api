# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::PaymentsController, type: :request do
  let(:organization) { create(:organization) }

  describe "POST /api/v1/payments" do
    subject do
      post_with_token(
        organization,
        "/api/v1/payments",
        {payment: params}
      )
    end

    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, organization:, customer:) }
    let(:params) do
      {
        invoice_id: invoice.id,
        amount_cents: 100,
        reference: 'ref1'
      }
    end

    let(:payment) { create(:payment, payable: invoice) }

    before do
      allow(ManualPayments::CreateService).to receive(:call).and_return(
        BaseService::Result.new.tap { |r| r.payment = payment }
      )
    end

    include_examples 'requires API permission', 'payment', 'write'

    it "delegates to ManualPayments::CreateService", :aggregate_failures do
      subject

      expect(ManualPayments::CreateService).to have_received(:call).with(organization:, params:)

      expect(response).to have_http_status(:success)
      expect(json[:payment][:lago_id]).to eq(payment.id)
      expect(json[:payment][:invoice_id]).to eq(payment.payable.id)
    end
  end

  describe "GET /api/v1/payments" do
    subject { get_with_token(organization, "/api/v1/payments", params) }

    let(:params) { {} }

    include_examples 'requires API permission', 'payment', 'read'

    it "returns organization's payments", :aggregate_failures do
      invoice = create(:invoice, organization:)
      payment_request = create(:payment_request, organization:)
      first_payment = create(:payment, payable: invoice)
      second_payment = create(:payment, payable: invoice)
      third_payment = create(:payment, payable: payment_request)

      subject

      expect(response).to have_http_status(:success)
      expect(json[:payments].count).to eq(3)
      expect(json[:payments].map { |r| r[:lago_id] }).to contain_exactly(
        first_payment.id,
        second_payment.id,
        third_payment.id
      )
    end

    context "with a not found invoice", :aggregate_failures do
      let(:params) { {invoice_id: SecureRandom.uuid} }

      before do
        invoice = create(:invoice, organization:)
        create(:payment, payable: invoice)
      end

      it "returns an empty result" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:payments]).to be_empty
      end
    end

    context "with invoice" do
      let(:invoice) { create(:invoice, organization:) }
      let(:params) { {invoice_id: invoice.id} }
      let(:first_payment) { create(:payment, payable: invoice) }

      before do
        first_payment
        create(:payment)
      end

      it "returns invoices's payments", :aggregate_failures do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:success)
          expect(json[:payments].map { |r| r[:lago_id] }).to contain_exactly(first_payment.id)
          expect(json[:payments].first[:invoice_id]).to eq(invoice.id)
        end
      end
    end
  end

  describe 'GET /api/v1/payments/:id' do
    subject { get_with_token(organization, "/api/v1/payments/#{id}") }

    let(:customer) { create(:customer, organization:) }
    let(:invoice) { create(:invoice, customer:, organization:) }
    let(:payment) { create(:payment, payable: invoice) }

    context 'when payment exists' do
      let(:id) { payment.id }

      include_examples 'requires API permission', 'payment', 'read'

      it 'returns the payment' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(json[:payment][:lago_id]).to eq(payment.id)
        end
      end
    end

    context 'when payment for a payment request exits' do
      let(:payment_request) { create(:payment_request, customer:, organization:) }
      let(:payment) { create(:payment, payable: payment_request) }
      let(:id) { payment.id }

      before do
        create(:payment_request_applied_invoice, invoice:, payment_request:)
      end

      include_examples 'requires API permission', 'payment', 'read'

      it 'returns the payment' do
        subject

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(json[:payment][:lago_id]).to eq(payment.id)
          expect(json[:payment][:invoice_id].first).to eq(invoice.id)
        end
      end
    end

    context 'when payment does not exist' do
      let(:id) { SecureRandom.uuid }

      it 'returns a not found error' do
        subject

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
