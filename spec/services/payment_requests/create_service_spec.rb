# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::CreateService, type: :service do
  subject(:create_service) { described_class.new(organization:, params:) }

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:customer) { create(:customer, organization:) }

  let(:first_invoice) { create(:invoice, customer:, payment_overdue: true) }
  let(:second_invoice) { create(:invoice, customer:, payment_overdue: true) }
  let(:params) do
    {
      external_customer_id: customer.external_id,
      email: "john.doe@example.com",
      lago_invoice_ids: [first_invoice.id, second_invoice.id]
    }
  end

  around { |test| lago_premium!(&test) }

  before { organization.update!(premium_integrations: ["dunning"]) }

  describe "#call" do
    context "when organization is not premium" do
      before do
        allow(License).to receive(:premium?).and_return(false)
      end

      it "returns not allowed failure", :aggregate_failures do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("premium_addon_feature_missing")
      end
    end

    context "when organization does not have premium dunning integration" do
      before do
        allow(organization).to receive(:premium_integrations).and_return([])
      end

      it "returns not allowed failure", :aggregate_failures do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("premium_addon_feature_missing")
      end
    end

    context "when customer does not exist" do
      before { params[:external_customer_id] = "non-existing-id" }

      it "returns not found failure", :aggregate_failures do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("customer")
      end
    end

    context "when invoices are not found" do
      before { params[:lago_invoice_ids] = [] }

      it "returns not found failure", :aggregate_failures do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.resource).to eq("invoice")
      end
    end

    context "when invoices are not overdue" do
      before { first_invoice.update!(payment_overdue: false) }

      it "returns not allowed failure", :aggregate_failures do
        result = create_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("invoices_not_overdue")
      end
    end

    it "creates a payment request" do
      expect { create_service.call }.to change { customer.payment_requests.count }.by(1)
    end

    it "assigns the invoices to the created payment request" do
      result = create_service.call

      expect(result.payment_request.invoices.count).to eq(2)
    end

    it "delivers a webhook" do
      create_service.call
      expect(SendWebhookJob).to have_been_enqueued.with("payment_request.created", PaymentRequest)
    end

    it "returns the payment request", :aggregate_failures do
      result = create_service.call

      expect(result.payment_request).to be_a(PaymentRequest)
      expect(result.payment_request).to have_attributes(
        organization:,
        customer:,
        amount_cents: first_invoice.total_amount_cents + second_invoice.total_amount_cents,
        amount_currency: "EUR",
        email: "john.doe@example.com"
      )
    end
  end
end
