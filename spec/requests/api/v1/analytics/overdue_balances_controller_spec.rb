# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::Analytics::OverdueBalancesController, type: :request do
  describe "GET /analytics/overdue_balances" do
    let(:customer) { create(:customer, organization:) }
    let(:organization) { create(:organization, created_at: DateTime.new(2023, 11, 1)) }

    it "returns the overdue balance" do
      travel_to(DateTime.new(2024, 1, 15)) do
        create(:invoice, customer:, organization:)
        i1 = create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 2.months.ago, total_amount_cents: 1000)
        i2 = create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 5.days.ago, total_amount_cents: 2000)
        i3 = create(:invoice, customer:, organization:, payment_overdue: true, payment_due_date: 1.day.ago, total_amount_cents: 3000)

        get_with_token(organization, "/api/v1/analytics/overdue_balance")

        expect(response).to have_http_status(:success)
        expect(json[:overdue_balances]).to match_array(
          [
            {
              month: "2023-11-01T00:00:00.000Z",
              amount_cents: "1000.0",
              currency: "EUR",
              lago_invoice_ids: [i1.id]
            },
            {
              month: "2024-01-01T00:00:00.000Z",
              amount_cents: "5000.0",
              currency: "EUR",
              lago_invoice_ids: match_array([i2.id, i3.id])
            }
          ]
        )
      end
    end
  end
end
