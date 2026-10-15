# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Analytics::GrossRevenuesController do
  describe "GET /analytics/gross_revenue" do
    subject { get_with_token(organization, "/api/v1/analytics/gross_revenue", params) }

    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization) }
    let(:billing_entity) { create(:billing_entity, organization: organization) }
    let(:params) { {} }

    before do
      allow(Analytics::GrossRevenuesService).to receive(:call).and_call_original
    end

    context "when licence is premium", :premium do
      include_examples "requires API permission", "analytic", "read"

      it "returns the gross revenue" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:gross_revenues]).to eq([])
        expect(Analytics::GrossRevenuesService).to have_received(:call).with(organization, billing_entity_id: nil, currency: nil, months: nil, external_customer_id: nil)
      end

      context "when the organization has finalized invoices" do
        it "returns integer amounts and counts" do
          travel_to(DateTime.new(2024, 1, 15)) do
            create(:invoice, customer:, organization:, status: :finalized, total_amount_cents: 1000, issuing_date: DateTime.new(2024, 1, 5))
            create(:invoice, customer:, organization:, status: :finalized, total_amount_cents: 2000, issuing_date: DateTime.new(2024, 1, 6))

            subject

            expect(response).to have_http_status(:success)
            expect(json[:gross_revenues]).to eq(
              [
                {
                  month: "2024-01-01T00:00:00.000Z",
                  amount_cents: 3000,
                  currency: "EUR",
                  invoices_count: 2,
                  billing_entity_id: organization.default_billing_entity.id
                }
              ]
            )
          end
        end
      end

      context "when sending params" do
        let(:params) { {billing_entity_code: billing_entity.code} }

        it "calls the service with the billing_entity_id" do
          subject
          expect(Analytics::GrossRevenuesService).to have_received(:call).with(organization, billing_entity_id: billing_entity.id, currency: nil, months: nil, external_customer_id: nil)
        end
      end
    end

    context "when licence is not premium" do
      it "returns the gross revenue" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:gross_revenues]).to eq([])
      end
    end
  end
end
