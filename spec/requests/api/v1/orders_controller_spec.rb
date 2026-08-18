# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::OrdersController do
  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote:) }
  let(:order) { create(:order, organization:, customer:, order_form:) }

  describe "GET /api/v1/orders" do
    subject { get_with_token(organization, "/api/v1/orders") }

    let(:one_off_quote) { create(:quote, organization:, customer:, order_type: :one_off) }
    let(:order_form_two) { create(:order_form, :signed, organization:, customer:, quote: one_off_quote) }
    let!(:order_two) { create(:order, organization:, customer:, order_form: order_form_two) }

    before { create(:order, organization:, customer:, order_form:) }

    include_examples "requires API permission", "order", "read"

    it "returns a list of orders" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:orders].count).to eq(2)
      expect(json[:orders].first).to have_key(:billing_snapshot)
    end

    context "when filtering by status" do
      subject { get_with_token(organization, "/api/v1/orders", {status: "created"}) }

      it "returns only matching orders" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:orders].count).to eq(2)
      end
    end

    context "when filtering by order_type" do
      subject { get_with_token(organization, "/api/v1/orders", {order_type: "one_off"}) }

      it "returns only matching orders" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:orders].count).to eq(1)
        expect(json[:orders].first[:lago_id]).to eq(order_two.id)
      end
    end

    context "when the order_forms feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "GET /api/v1/orders/:id" do
    subject { get_with_token(organization, "/api/v1/orders/#{order.id}") }

    before { order }

    include_examples "requires API permission", "order", "read"

    it "returns the order" do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order][:lago_id]).to eq(order.id)
      expect(json[:order][:number]).to eq(order.number)
      expect(json[:order][:status]).to eq("created")
      expect(json[:order]).to have_key(:billing_snapshot)
    end

    context "when order does not exist" do
      subject { get_with_token(organization, "/api/v1/orders/#{SecureRandom.uuid}") }

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("order")
      end
    end

    context "when the order_forms feature flag is disabled" do
      let(:organization) { create(:organization) }

      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end

  describe "POST /api/v1/orders/:id/execute" do
    subject { post_with_token(organization, "/api/v1/orders/#{order.id}/execute", params) }

    let(:params) { {} }
    let(:customer) { create(:customer, organization:, currency: "EUR") }
    let(:quote) { create(:quote, organization:, customer:, order_type: :one_off) }
    let(:quote_version) do
      create(:quote_version, :approved, :with_one_off_billing_items, quote:, organization:)
    end
    let(:order_form) { create(:order_form, :signed, organization:, customer:, quote_version:) }
    let(:order) { create(:order, organization:, customer:, order_form:, execution_mode:) }
    let(:execution_mode) { :order_only }

    before { order }

    include_examples "requires API permission", "order", "write"

    it "executes the order", :premium do
      subject

      expect(response).to have_http_status(:ok)
      expect(json[:order][:lago_id]).to eq(order.id)
      expect(json[:order][:status]).to eq("executed")
      expect(json[:order][:executed_at]).to be_present
      expect(json[:order][:execution_record][:execution_mode]).to eq("order_only")
    end

    context "with the execute_in_lago mode", :premium do
      let(:execution_mode) { :execute_in_lago }

      it "bills the order and returns the invoice it created" do
        expect { subject }.to change(Invoice, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(json[:order][:status]).to eq("executed")
        expect(json[:order][:execution_record][:invoice_id]).to eq(customer.invoices.sole.id)
      end
    end

    context "when the order has already been executed", :premium do
      let(:order) { create(:order, :executed_order_only, organization:, customer:, order_form:) }

      it "returns the order untouched" do
        executed_at = order.executed_at

        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order][:status]).to eq("executed")
        expect(order.reload.executed_at).to eq(executed_at)
      end
    end

    context "when a previous execution failed", :premium do
      let(:order) { create(:order, :failed, organization:, customer:, order_form:, execution_mode: :order_only) }

      it "executes the order again" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:order][:status]).to eq("executed")
        expect(json[:order][:execution_record][:errors]).to eq([])
      end
    end

    context "when the order carries no execution mode", :premium do
      let(:execution_mode) { nil }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(:execution_mode)
      end

      context "when an execution mode is provided" do
        let(:params) { {order: {execution_mode: "order_only"}} }

        it "executes the order with that mode" do
          subject

          expect(response).to have_http_status(:ok)
          expect(json[:order][:status]).to eq("executed")
          expect(order.reload.execution_mode).to eq("order_only")
        end
      end
    end

    context "when the provided execution mode is invalid", :premium do
      let(:params) { {order: {execution_mode: "whenever"}} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(:execution_mode)
      end
    end

    context "when the provided execution mode changes an executed order", :premium do
      let(:order) { create(:order, :executed_order_only, organization:, customer:, order_form:) }
      let(:params) { {order: {execution_mode: "execute_in_lago"}} }

      it "returns a validation error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to include(:status)
      end
    end

    context "when the execution fails", :premium do
      let(:execution_mode) { :execute_in_lago }

      let(:failed_result) do
        Invoices::CreateOneOffService::Result.new.tap do |failed|
          failed.single_validation_failure!(field: :currency, error_code: "currencies_does_not_match")
        end
      end

      before { allow(Invoices::CreateOneOffService).to receive(:call!).and_raise(failed_result.error) }

      it "surfaces the error and marks the order failed" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:error_details]).to eq({currency: ["currencies_does_not_match"]})
        expect(order.reload.failed?).to eq(true)
      end
    end

    context "when the execution lock cannot be acquired", :premium do
      before { allow(Orders::ExecuteService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock) }

      it "returns a lock acquisition error" do
        subject

        expect(response).to have_http_status(:unprocessable_content)
        expect(json[:code]).to eq("lock_acquisition_failed")
      end
    end

    context "when order does not exist", :premium do
      subject { post_with_token(organization, "/api/v1/orders/#{SecureRandom.uuid}/execute") }

      it "returns not found" do
        subject

        expect(response).to be_not_found_error("order")
      end
    end

    context "without a premium license" do
      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end

    context "when the order_forms feature flag is disabled", :premium do
      let(:organization) { create(:organization) }

      it "returns forbidden" do
        subject

        expect(response).to have_http_status(:forbidden)
        expect(json[:code]).to eq("feature_unavailable")
      end
    end
  end
end
